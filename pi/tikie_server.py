#!/usr/bin/env python3
"""Tikie helper - the small service that runs on the Raspberry Pi.

It does the light work the iOS 6 app cannot: it asks yt-dlp for public TikTok video lists and fresh direct
URLs, and hands the app a tiny JSON. Video bytes normally stream straight from TikTok's CDN to the phone; only
the optional /proxy endpoint (used as a fallback and for "save") moves the actual video through the Pi.

No login, no posting - read only. yt-dlp is the maintained part: when TikTok changes, `pip install -U yt-dlp`
on the Pi fixes it without touching the app.

Endpoints (all JSON unless noted):
  GET /health
  GET /discover?cat=<categoryType>&count=20[&maxh=1280]  a fresh batch from TikTok's logged-out Explore feed for one
                                       topic, ready to play (H.264 URL + the session headers) with the features the
                                       app's recommender learns from (topic, hashtags, sound, language...)
  GET /user?name=<handle>&count=30     a creator's recent videos (list of lightweight items)
  GET /resolve?id=<id|url>[&user=<handle>][&vcodec=h264][&maxh=1280]  one video with a fresh playable URL and
                                       the headers to send; an H.264 rendition by default (iOS 6 has no HEVC decoder)
  GET /comments?id=<id|url>&count=40    top-level comments (best effort; empty if TikTok withholds them)
  GET /replies?id=<id>&cid=<comment id>&count=20  the replies under one comment
  GET /profile?name=<handle>[&maxh=]   a creator: name, avatar, bio, link, counts, live room, the newest posts (ready
                                       to play) and a cursor for more
  GET /posts?sec=<secUid>&cursor=<ms>[&maxh=]  more of a creator's posts (older than the cursor)
  GET /search?q=<words>&offset=0[&maxh=]  TikTok search: videos ready to play, and creators when TikTok shows some
  GET /suggest?q=<start of words>      what TikTok suggests while typing
  GET /tag?name=<hashtag>&cursor=0[&maxh=]  a hashtag: its counts and videos ready to play
  GET /sound?id=<music id>&cursor=0[&maxh=]  a sound: title, author, cover, the sound itself and videos using it
  GET /live?room=<room id>             a live room: on or not, title, viewers, owner, streams (FLV, HLS if any)
  GET /lives?count=20                  live rooms seen lately among Explore authors
  GET /expand?u=<tiktok link>          where a (short) TikTok link leads
  GET /proxy?u=<playUrl>               streams the video bytes through the Pi (fallback / save); CDN hosts only
  GET /yt/resolve?id=<youtube id|url>  fresh YouTube stream URLs for the Tubie app (see the YouTube section)
Set TIKIE_KEY to require ?k=<key> (or X-Tikie-Key header) on every call when you expose this beyond the LAN.
"""
import base64
import hashlib
import http.cookiejar
import json
import os
import random
import re
import sys
import time
import threading
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    import yt_dlp
except ImportError:
    sys.exit("tikie: yt-dlp is not installed (pip install yt-dlp)")

KEY = os.environ.get("TIKIE_KEY", "")
PORT = int(os.environ.get("TIKIE_PORT", "8730"))
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/124.0.0.0 Safari/537.36")
CDN_HOST_RE = re.compile(r"\.(tiktokcdn[-\w]*\.com|tiktokv\.com|tiktok\.com|ttwstatic\.com|byteoversea\.com|ibyteimg\.com|akamaized\.net)$", re.I)

# --- tiny TTL cache -------------------------------------------------------

class TTLCache:
    def __init__(self):
        self._d = {}
        self._lock = threading.Lock()
        self._puts = 0

    def get(self, key):
        with self._lock:
            item = self._d.get(key)
            if not item:
                return None
            if item[0] < time.time():
                self._d.pop(key, None)
                return None
            return item[1]

    def put(self, key, value, ttl):
        with self._lock:
            now = time.time()
            self._d[key] = (now + ttl, value)
            self._puts += 1
            if self._puts % 500 == 0:   # expired entries are otherwise only dropped when read again
                for k in [k for k, v in self._d.items() if v[0] < now]:
                    del self._d[k]

CACHE = TTLCache()

# --- yt-dlp helpers -------------------------------------------------------

_YDL_LOCK = threading.Lock()

def _ydl(opts):
    base = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": False,
        "http_headers": {"User-Agent": UA, "Referer": "https://www.tiktok.com/"},
        "extractor_args": {"tiktok": {"app_name": ["tiktok_web"]}},
    }
    base.update(opts)
    return yt_dlp.YoutubeDL(base)

def video_id(s):
    s = (s or "").strip()
    m = re.search(r"/video/(\d{6,25})", s)
    if m:
        return m.group(1)
    m = re.fullmatch(r"\d{6,25}", s)
    return m.group(0) if m else None

def norm_user(name):
    name = (name or "").strip().lstrip("@")
    return re.sub(r"[^A-Za-z0-9_.]", "", name)

def thumb_of(info):
    t = info.get("thumbnail")
    if t:
        return t
    thumbs = info.get("thumbnails") or []
    return thumbs[-1]["url"] if thumbs else None

def item_from_info(info):
    """A lightweight list item (no play URL - that is fetched lazily by /resolve)."""
    vid = str(info.get("id") or "")
    uploader = info.get("uploader") or info.get("creator") or info.get("channel") or ""
    return {
        "id": vid,
        "author": norm_user(uploader) or norm_user(info.get("uploader_id")),
        "authorName": info.get("uploader") or "",
        "desc": info.get("description") or info.get("title") or "",
        "cover": thumb_of(info),
        "duration": info.get("duration") or 0,
        "likes": info.get("like_count") or 0,
        "comments": info.get("comment_count") or 0,
        "plays": info.get("view_count") or 0,
        "created": info.get("timestamp") or 0,
        "type": "video",
        "url": info.get("webpage_url") or ("https://www.tiktok.com/@%s/video/%s" % (norm_user(uploader), vid) if uploader and vid else None),
    }

def user_list(name, count):
    name = norm_user(name)
    if not name:
        return []
    ckey = "user:%s:%d" % (name, count)
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    url = "https://www.tiktok.com/@%s" % name
    opts = {"extract_flat": "in_playlist", "playlistend": max(1, min(count, 60))}
    with _YDL_LOCK, _ydl(opts) as ydl:
        info = ydl.extract_info(url, download=False)
    entries = info.get("entries") or []
    items = []
    for e in entries:
        if not e:
            continue
        it = item_from_info(e)
        if not e.get("formats") and not e.get("duration"):
            it["type"] = "photo"   # a photo post (slideshow): /resolve reads its pictures from the post's page
        if not it["author"]:
            it["author"] = name
        if it["id"]:
            items.append(it)
    CACHE.put(ckey, items, 600)
    return items

def _cookie_header(ydl, for_url):
    """TikTok's CDN URLs only serve to the session that resolved them: gather that session's TikTok cookies
    (ttwid etc.) so the player - or our /proxy - can send them."""
    host = urllib.parse.urlparse(for_url or "").hostname or ""
    parts = []
    try:
        for c in ydl.cookiejar:
            dom = (c.domain or "").lstrip(".")
            if dom and (host.endswith(dom) or "tiktok" in dom):
                parts.append("%s=%s" % (c.name, c.value))
    except Exception:
        pass
    return "; ".join(parts)

def _long_side(f):
    return max(f.get("width") or 0, f.get("height") or 0)

def pick_format(info, vcodec, maxh):
    """TikTok serves each video as h265 (bytevc1) and usually also as h264. yt-dlp's default pick prefers h265,
    which iOS 6 cannot decode (the sound plays over a black picture), so choose an h264 rendition: the largest whose
    long side fits maxh (the device's screen), else the smallest above it. The watermarked "download" file is h264
    too and is the last resort. None = no preference or nothing suitable: the caller keeps yt-dlp's pick."""
    if vcodec != "h264":
        return None
    fmts = [f for f in (info.get("formats") or []) if f.get("url")]
    h264 = [f for f in fmts if (f.get("vcodec") or "").lower().startswith(("h264", "avc"))]
    cands = [f for f in h264 if f.get("format_id") != "download"] or h264
    if not cands:
        return None
    sized = [f for f in cands if _long_side(f) > 0]
    fit = [f for f in sized if _long_side(f) <= maxh]
    if fit:
        return max(fit, key=lambda f: (_long_side(f), f.get("tbr") or 0))
    if sized:
        return min(sized, key=lambda f: (_long_side(f), -(f.get("tbr") or 0)))
    return cands[0]

def resolve(ref, user=None, vcodec="h264", maxh=1280):
    vid = video_id(ref)
    if not vid:
        raise ValueError("no video id")
    ckey = "resolve:%s:%s:%d" % (vid, vcodec, maxh)
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    if re.match(r"^https?://", ref or ""):
        url = ref
    elif user:
        url = "https://www.tiktok.com/@%s/video/%s" % (norm_user(user), vid)
    else:
        url = "https://www.tiktok.com/@_/video/%s" % vid   # TikTok redirects to the right handle
    try:
        out = _resolve_ytdlp(url, vcodec, maxh)
    except Exception as e:
        # yt-dlp has no answer for a photo post ("No video formats found") and now and then fails on a video too:
        # the post's own page carries the same data
        out = resolve_from_page(vid, user, maxh)
        if not out:
            raise e
    CACHE.put(ckey, out, 1800)
    return out

def _resolve_ytdlp(url, vcodec, maxh):
    with _YDL_LOCK, _ydl({"noplaylist": True}) as ydl:
        info = ydl.extract_info(url, download=False)
        chosen = pick_format(info, vcodec, maxh)
        if chosen:
            play = chosen.get("url")
        else:
            play = info.get("url")
            fmts = info.get("formats") or []
            if not play and fmts:
                mp4s = [f for f in fmts if (f.get("ext") == "mp4" and f.get("url"))]
                mp4s.sort(key=lambda f: (f.get("tbr") or 0))
                play = (mp4s[-1] if mp4s else fmts[-1]).get("url")
        headers = {"User-Agent": UA, "Referer": "https://www.tiktok.com/"}
        if isinstance(info.get("http_headers"), dict):
            headers.update(info["http_headers"])
        if chosen and isinstance(chosen.get("http_headers"), dict):
            headers.update(chosen["http_headers"])
        cookie = _cookie_header(ydl, play)
        if cookie:
            headers["Cookie"] = cookie
    src = chosen or info
    out = item_from_info(info)
    out["playUrl"] = play
    out["headers"] = headers
    out["width"] = src.get("width") or 0
    out["height"] = src.get("height") or 0
    out["vcodec"] = src.get("vcodec") or ""
    out["formatId"] = src.get("format_id") or ""
    out["music"] = (info.get("track") or info.get("artist") or "")
    if play:
        CACHE.put("hdr:" + play, headers, 1800)     # /proxy reuses the exact headers this URL needs
    return out

def _comment_item(c):
    user = c.get("user") or {}
    return {"cid": str(c.get("cid") or ""),
            "author": user.get("unique_id") or user.get("nickname") or "",
            "authorName": user.get("nickname") or "",
            "avatar": _jpeg((user.get("avatar_thumb") or {}).get("url_list")),
            "text": (c.get("text") or "").strip(),
            "likes": c.get("digg_count") or 0,
            "replies": c.get("reply_comment_total") or 0,
            "pinned": bool(c.get("author_pin")),
            "time": c.get("create_time") or 0}

def comments(ref, count):
    """Top-level comments. yt-dlp no longer extracts TikTok comments, but TikTok's own web endpoint answers
    without a login or a request signature, 20 per page."""
    vid = video_id(ref)
    if not vid:
        return []
    count = max(1, min(count, 100))
    ckey = "comments:%s:%d" % (vid, count)
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    out = []
    ok = False
    cursor = 0
    try:
        for _ in range(6):
            q = urllib.parse.urlencode({"aid": "1988", "aweme_id": vid, "count": 20, "cursor": cursor})
            req = urllib.request.Request("https://www.tiktok.com/api/comment/list/?" + q,
                                         headers={"User-Agent": UA, "Referer": "https://www.tiktok.com/"})
            with urllib.request.urlopen(req, timeout=15) as r:
                data = json.loads(r.read().decode("utf-8", "replace") or "{}")
            ok = True
            for c in data.get("comments") or []:
                text = (c.get("text") or "").strip()
                if not text:
                    continue
                out.append(_comment_item(c))
            if len(out) >= count or not data.get("has_more"):
                break
            cursor = data.get("cursor") or (cursor + 20)
    except Exception as e:
        sys.stderr.write("comments failed for %s: %s\n" % (vid, e))
    out = out[:count]
    CACHE.put(ckey, out, 600 if ok else 60)   # a failure is retried after a minute, not ten
    return out

# --- Discovery: TikTok's logged-out Explore feed --------------------------
# tiktok.com/explore serves topic feeds to visitors without an account or a request signature, and every call
# returns a fresh batch. Its items carry ready H.264 URLs that play with the cookies of the session that fetched
# them, so a batch costs the Pi one small JSON request and no yt-dlp run.

WEB_SESSION_TTL = 6 * 3600
_WEB_LOCK = threading.Lock()
_WEB = {"opener": None, "jar": None, "born": 0.0}

def _web_session(fresh=False):
    """The logged-out tiktok.com session (ttwid, tt_chain_token...) the Explore API and its video URLs belong to."""
    with _WEB_LOCK:
        if fresh or _WEB["opener"] is None or time.time() - _WEB["born"] > WEB_SESSION_TTL:
            jar = http.cookiejar.CookieJar()
            opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
            req = urllib.request.Request("https://www.tiktok.com/explore",
                                         headers={"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9"})
            with opener.open(req, timeout=20) as r:
                r.read()
            _WEB.update(opener=opener, jar=jar, born=time.time())
        return _WEB["opener"], _WEB["jar"]

def _pick_h264_web(bitrate_info, maxh):
    """The Explore item's H.264 rendition whose long side best fits maxh (same rule as pick_format)."""
    cands = []
    for b in bitrate_info or []:
        if not str(b.get("CodecType") or "").lower().startswith("h264"):
            continue
        pa = b.get("PlayAddr") or {}
        urls = pa.get("UrlList") or []
        if not urls:
            continue
        w, h = pa.get("Width") or 0, pa.get("Height") or 0
        cands.append({"long": max(w, h), "rate": b.get("Bitrate") or 0, "url": urls[0], "w": w, "h": h})
    if not cands:
        return None
    fit = [c for c in cands if 0 < c["long"] <= maxh]
    if fit:
        return max(fit, key=lambda c: (c["long"], c["rate"]))
    return min(cands, key=lambda c: (c["long"] or 10 ** 6, -c["rate"]))

_SENSITIVE_COOKIES = {
    "sessionid", "sessionid_ss", "sid_tt", "sid_guard", "uid_tt", "uid_tt_ss",
    "passport_csrf_token", "passport_csrf_token_default", "csrf_session_id"
}

def _session_headers(jar, allow_sensitive=False):
    headers = {"User-Agent": UA, "Referer": "https://www.tiktok.com/"}
    if not jar:
        return headers
    cookies = []
    for c in jar:
        if "tiktok" in (c.domain or ""):
            if not allow_sensitive and c.name.lower() in _SENSITIVE_COOKIES:
                continue
            cookies.append("%s=%s" % (c.name, c.value))
    if cookies:
        headers["Cookie"] = "; ".join(cookies)
    return headers

def _jpeg(urls):
    """The JPEG one among an image's URLs (iOS 6 decodes no WebP or HEIC), else the first."""
    urls = [u for u in (urls or []) if u]
    for u in urls:
        if re.search(r"\.jpe?g(\?|$)", u, re.I):
            return u
    return urls[0] if urls else ""

# Live rooms seen among the authors of Explore items (their "roomId" is set while they are live): the only way a
# visitor without an account can find live streams - TikTok's own live listings want a signed request.
EXPLORE_TOPICS = list(range(100, 120))
LIVE_SEEN_TTL = 30 * 60       # (a stream lasts hours; the app checks a room is still on before playing it)
_LIVE_LOCK = threading.Lock()
_LIVE_SEEN = {}          # roomId -> {"room", "user", "name", "avatar", "seen"}

def _note_live(a):
    room = str(a.get("roomId") or "")
    if not room or room == "0":
        return ""
    now = time.time()
    with _LIVE_LOCK:
        _LIVE_SEEN[room] = {"room": room, "user": norm_user(a.get("uniqueId")), "name": a.get("nickname") or "",
                            "avatar": _jpeg([a.get("avatarThumb"), a.get("avatarMedium")]), "seen": now}
        for k in [k for k, v in _LIVE_SEEN.items() if now - v["seen"] > LIVE_SEEN_TTL]:
            del _LIVE_SEEN[k]
    return room

def item_from_web(it, maxh):
    """One web item (an Explore item, or a post read from its page) -> a list item ready to show, plus the features
    the app's recommender learns from. A video gets its H.264 URL; a photo post its pictures (JPEG) and, when TikTok
    gives one to a visitor, its sound."""
    if it.get("isAd") or it.get("privateItem") or it.get("secret"):
        return None
    vid = str(it.get("id") or "")
    if not vid:
        return None
    v = it.get("video") or {}
    a = it.get("author") or {}
    m = it.get("music") or {}
    st = it.get("stats") or {}
    handle = norm_user(a.get("uniqueId"))
    tags = []
    for t in it.get("textExtra") or []:
        name = (t.get("hashtagName") or "").strip().lower()
        if name and name not in tags:
            tags.append(name)
    out = {
        "id": vid,
        "author": handle,
        "authorName": a.get("nickname") or handle,
        "authorAvatar": _jpeg([a.get("avatarThumb"), a.get("avatarMedium")]),
        "authorLive": _note_live(a),
        "desc": it.get("desc") or "",
        "cover": v.get("originCover") or v.get("cover") or "",
        "duration": v.get("duration") or 0,
        "likes": st.get("diggCount") or 0,
        "comments": st.get("commentCount") or 0,
        "plays": st.get("playCount") or 0,
        "url": "https://www.tiktok.com/@%s/video/%s" % (handle or "_", vid),
        "music": m.get("title") or "",
        "musicId": str(m.get("id") or ""),
        "musicOriginal": bool(m.get("original")),
        "musicAuthor": m.get("authorName") or "",
        "musicCover": _jpeg([m.get("coverMedium"), m.get("coverThumb"), m.get("coverLarge")]),
        "category": it.get("CategoryType") or 0,
        "tags": tags[:10],
        "lang": it.get("textLanguage") or "",
        "created": it.get("createTime") or 0,
    }
    # captions: TikTok's speech recognition of the video (ASR) and machine translations of it (MT), as WebVTT
    subs = []
    for s in v.get("subtitleInfos") or []:
        if s.get("Url") and str(s.get("Format") or "webvtt").lower() == "webvtt":
            subs.append({"lang": s.get("LanguageCodeName") or "", "source": s.get("Source") or "", "url": s["Url"]})
    if subs:
        out["subtitles"] = subs
    images = []
    for img in (it.get("imagePost") or {}).get("images") or []:
        u = _jpeg((img.get("imageURL") or {}).get("urlList"))
        if u:
            images.append({"url": u, "w": img.get("imageWidth") or 0, "h": img.get("imageHeight") or 0})
    if images:
        out.update({"type": "photo", "images": images, "cover": out["cover"] or images[0]["url"],
                    "musicUrl": m.get("playUrl") or ""})
        return out
    pick = _pick_h264_web(v.get("bitrateInfo"), maxh)
    if not pick:
        return None
    out.update({"type": "video", "playUrl": pick["url"], "width": pick["w"], "height": pick["h"], "vcodec": "h264"})
    return out

def discover(cat, count, maxh):
    """A fresh Explore batch for one topic. Returns (items, headers): the headers (session cookies) play every URL."""
    count = max(1, min(count, 30))
    raw, jar = [], None
    for attempt in (0, 1):   # an empty answer usually means a stale session: start a new one and ask again
        opener, jar = _web_session(fresh=(attempt == 1))
        q = urllib.parse.urlencode({"aid": "1988", "count": count, "categoryType": cat})
        req = urllib.request.Request("https://www.tiktok.com/api/explore/item_list/?" + q,
                                     headers={"User-Agent": UA, "Referer": "https://www.tiktok.com/explore"})
        with opener.open(req, timeout=15) as r:
            data = json.loads(r.read().decode("utf-8", "replace") or "{}")
        raw = data.get("itemList") or []
        if raw:
            break
    headers = _session_headers(jar)
    items = []
    for it in raw:
        x = item_from_web(it, maxh)
        if x:
            items.append(x)
            if x.get("playUrl"):
                CACHE.put("hdr:" + x["playUrl"], headers, 6 * 3600)   # for the /proxy fallback
    return items, headers

# --- Posts, profiles and live rooms read the way the web app shows them to a visitor ---------

def _web_get(url, referer="https://www.tiktok.com/"):
    opener, jar = _web_session()
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Referer": referer, "Accept-Language": "en-US,en;q=0.9"})
    with opener.open(req, timeout=20) as r:
        return r.geturl(), r.read(), jar

def _rehydration(html):
    m = re.search(rb'<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">(.*?)</script>', html, re.S)
    if not m:
        return {}
    try:
        return json.loads(m.group(1)).get("__DEFAULT_SCOPE__") or {}
    except ValueError:
        return {}

def resolve_from_page(vid, user=None, maxh=1280):
    """A post read from its own page: photo posts (yt-dlp has nothing for them) and videos yt-dlp failed on."""
    try:
        final, html, jar = _web_get("https://www.tiktok.com/@%s/video/%s" % (norm_user(user) or "_", vid))
    except Exception as e:
        sys.stderr.write("page of %s failed: %s\n" % (vid, e))
        return None
    detail = _rehydration(html).get("webapp.video-detail") or {}
    it = (detail.get("itemInfo") or {}).get("itemStruct") or {}
    out = item_from_web(it, maxh) if it else None
    if not out:
        return None
    out["headers"] = _session_headers(jar)
    if out.get("playUrl"):
        CACHE.put("hdr:" + out["playUrl"], out["headers"], 6 * 3600)
    return out

def replies(ref, cid, count):
    """The replies under one comment (the same open web endpoint as the comments)."""
    vid = video_id(ref)
    cid = re.sub(r"\D", "", cid or "")
    if not vid or not cid:
        raise ValueError("id and cid are needed")
    count = max(1, min(count, 50))
    ckey = "replies:%s:%s:%d" % (vid, cid, count)
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    out, ok, cursor = [], False, 0
    try:
        for _ in range(3):
            q = urllib.parse.urlencode({"aid": "1988", "item_id": vid, "comment_id": cid, "count": 20, "cursor": cursor})
            req = urllib.request.Request("https://www.tiktok.com/api/comment/list/reply/?" + q,
                                         headers={"User-Agent": UA, "Referer": "https://www.tiktok.com/"})
            with urllib.request.urlopen(req, timeout=15) as r:
                data = json.loads(r.read().decode("utf-8", "replace") or "{}")
            ok = True
            for c in data.get("comments") or []:
                item = _comment_item(c)
                if item["text"]:
                    out.append(item)
            if len(out) >= count or not data.get("has_more"):
                break
            cursor = data.get("cursor") or (cursor + 20)
    except Exception as e:
        sys.stderr.write("replies failed for %s/%s: %s\n" % (vid, cid, e))
    out = out[:count]
    CACHE.put(ckey, out, 600 if ok else 60)
    return out

# --- Signed web API calls --------------------------------------------------
# Search, hashtags and sounds answer a logged-out visitor only when the query carries TikTok's X-Bogus signature:
# an RC4/MD5 checksum of the query, the User-Agent and the time, which TikTok's own web page computes the same way.
# The algorithm follows f2's xbogus.py (Apache-2.0, https://github.com/Johnserf-Seed/f2). Unsigned or wrongly signed
# requests get an empty 200 answer.

_XB_HEX = {c: i for i, c in enumerate("0123456789abcdef")}
_XB_ALPHABET = "Dkdpgh4ZKsQB80/Mfvw36XI1R25-WUAlEi7NLboqYTOPuzmFjJnryx9HVGcaStCe="
_DEVICE_ID = str(random.randint(7250000000000000000, 7351147085025500000))
_MS_TOKEN = "".join(random.choice("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_") for _ in range(126)) + "=="


def _rc4(key, data):
    s = list(range(256))
    j = 0
    for i in range(256):
        j = (j + s[i] + key[i % len(key)]) % 256
        s[i], s[j] = s[j], s[i]
    out = bytearray()
    i = j = 0
    for b in data:
        i = (i + 1) % 256
        j = (j + s[i]) % 256
        s[i], s[j] = s[j], s[i]
        out.append(b ^ s[(s[i] + s[j]) % 256])
    return bytes(out)


def _unhex(h):
    return bytes((_XB_HEX[h[k]] << 4) | _XB_HEX[h[k + 1]] for k in range(0, len(h), 2))


def x_bogus(query, ua=UA):
    """The X-Bogus value for a query string sent with the User-Agent `ua`."""
    md5 = lambda b: hashlib.md5(b).hexdigest()
    ua_sum = _unhex(md5(base64.b64encode(_rc4(b"\x00\x01\x0c", ua.encode("latin-1")))))
    empty_sum = _unhex(md5(_unhex("d41d8cd98f00b204e9800998ecf8427e")))
    query_sum = _unhex(md5(_unhex(md5(query.encode("utf-8")))))
    t, ct = int(time.time()), 536919696
    arr = [64, 0, 1, 12, query_sum[14], query_sum[15], empty_sum[14], empty_sum[15], ua_sum[14], ua_sum[15],
           t >> 24 & 255, t >> 16 & 255, t >> 8 & 255, t & 255, ct >> 24 & 255, ct >> 16 & 255, ct >> 8 & 255, ct & 255]
    check = 0
    for b in arr:
        check ^= b
    arr.append(check)
    garbled = bytes([2, 255]) + _rc4(b"\xff", bytes(arr))
    out = []
    for k in range(0, len(garbled), 3):
        n = (garbled[k] << 16) | (garbled[k + 1] << 8) | garbled[k + 2]
        out.append(_XB_ALPHABET[n >> 18 & 63] + _XB_ALPHABET[n >> 12 & 63] + _XB_ALPHABET[n >> 6 & 63] + _XB_ALPHABET[n & 63])
    return "".join(out)


def _web_params(page):
    """What TikTok's web page sends along with every API call."""
    return {"WebIdLastTime": str(int(time.time())), "aid": "1988", "app_language": "en", "app_name": "tiktok_web",
            "browser_language": "en-US", "browser_name": "Mozilla", "browser_online": "true", "browser_platform": "Win32",
            "browser_version": UA[len("Mozilla/"):], "channel": "tiktok_web", "cookie_enabled": "true",
            "device_id": _DEVICE_ID, "device_platform": "web_pc", "focus_state": "true", "from_page": page,
            "history_len": "3", "is_fullscreen": "false", "is_page_visible": "true", "language": "en", "os": "windows",
            "priority_region": "", "referer": "", "region": "CZ", "screen_height": "1080", "screen_width": "1920",
            "tz_name": "Europe/Prague", "webcast_language": "en"}


def _web_api(path, params, page, referer, sign=True, session_jar=None):
    """A tiktok.com web API call in the logged-out session -> (json, session headers). An empty answer is asked once
    more in a fresh session; ({}, headers) when TikTok still says nothing."""
    data, jar = {}, None
    for attempt in (0, 1):
        if session_jar is not None:
            jar = session_jar
            opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        else:
            opener, jar = _web_session(fresh=(attempt == 1))
        p = _web_params(page)
        p.update(params)
        p["msToken"] = _MS_TOKEN
        q = urllib.parse.urlencode(p, quote_via=urllib.parse.quote)
        if sign:
            q += "&X-Bogus=" + x_bogus(q)
        req = urllib.request.Request("https://www.tiktok.com%s?%s" % (path, q),
                                     headers={"User-Agent": UA, "Referer": referer, "Accept-Language": "en-US,en;q=0.9"})
        with opener.open(req, timeout=20) as r:
            body = r.read()
        if body:
            data = json.loads(body.decode("utf-8", "replace") or "{}")
            break
        if session_jar is not None:
            break
    return data, _session_headers(jar)


def _ready_items(raw, maxh, headers):
    """Web items -> list items ready to play (their URLs play with the session's headers, kept for /proxy)."""
    items = []
    for it in raw or []:
        x = item_from_web(it, maxh)
        if x:
            items.append(x)
            if x.get("playUrl"):
                CACHE.put("hdr:" + x["playUrl"], headers, 6 * 3600)
    return items


def search(query, offset, maxh):
    """TikTok's search ("Top"): 12 videos a page, and creators when TikTok puts a card of them first."""
    query = re.sub(r"\s+", " ", query or "").strip()[:100]
    if not query:
        raise ValueError("no query")
    offset = max(0, offset)
    ckey = "search:%s:%d:%d" % (query.lower(), offset, maxh)
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    data, headers = _web_api("/api/search/general/full/", {"keyword": query, "offset": str(offset), "search_source": "normal_search"},
                             "search", "https://www.tiktok.com/search?q=" + urllib.parse.quote(query))
    raw, users = [], []
    for e in data.get("data") or []:
        if e.get("item"):
            raw.append(e["item"])
        for u in e.get("user_list") or []:
            ui = u.get("user_info") or {}
            handle = norm_user(ui.get("unique_id"))
            if handle:
                users.append({"handle": handle, "name": ui.get("nickname") or handle, "bio": ui.get("signature") or "",
                              "avatar": _jpeg((ui.get("avatar_thumb") or {}).get("url_list")),
                              "followers": ui.get("follower_count") or 0, "verified": bool(ui.get("custom_verify")),
                              "liveRoom": str(ui.get("room_id") or "") if ui.get("room_id") else ""})
    items = _ready_items(raw, maxh, headers)
    out = {"items": items, "users": users, "hasMore": bool(data.get("has_more")),
           "offset": int(data.get("cursor") or offset + len(raw)), "headers": headers}
    CACHE.put(ckey, out, 300 if (items or users) else 30)
    return out


def suggest(query):
    """What TikTok suggests for the start of a search (no signature needed)."""
    query = re.sub(r"\s+", " ", query or "").strip()[:60]
    if not query:
        return []
    ckey = "suggest:%s" % query.lower()
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    q = urllib.parse.urlencode({"aid": "1988", "keyword": query})
    final, body, jar = _web_get("https://www.tiktok.com/api/search/general/sug/?" + q,
                                referer="https://www.tiktok.com/search?q=" + urllib.parse.quote(query))
    data = json.loads(body.decode("utf-8", "replace") or "{}") if body else {}
    out = []
    for s in data.get("sug_list") or []:
        c = (s.get("content") or "").strip()
        if c and c.lower() not in [x.lower() for x in out]:
            out.append(c)
    out = out[:10]
    CACHE.put(ckey, out, 600)
    return out


def tag(name, cursor, maxh):
    """A hashtag: its name and counts, and a page of its videos (30)."""
    name = (name or "").strip().lstrip("#").strip()[:100]
    if not name:
        raise ValueError("no hashtag")
    referer = "https://www.tiktok.com/tag/" + urllib.parse.quote(name)
    ikey = "taginfo:%s" % name.lower()
    info = CACHE.get(ikey)
    if info is None:
        data, headers = _web_api("/api/challenge/detail/", {"challengeName": name}, "hashtag", referer)
        ci = data.get("challengeInfo") or {}
        ch = ci.get("challenge") or {}
        if not ch.get("id"):
            CACHE.put(ikey, {}, 60)
            return {"tag": None, "items": [], "cursor": 0, "hasMore": False}
        st = ci.get("statsV2") or ci.get("stats") or ch.get("stats") or {}
        info = {"id": str(ch["id"]), "name": ch.get("title") or name, "desc": ch.get("desc") or "",
                "videos": int(st.get("videoCount") or 0), "views": int(st.get("viewCount") or 0),
                "cover": _jpeg([ch.get("profileMedium"), ch.get("coverMedium"), ch.get("profileThumb")])}
        CACHE.put(ikey, info, 3600)
    if not info:
        return {"tag": None, "items": [], "cursor": 0, "hasMore": False}
    ckey = "tagitems:%s:%d:%d" % (info["id"], cursor, maxh)
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    data, headers = _web_api("/api/challenge/item_list/", {"challengeID": info["id"], "count": "30", "cursor": str(cursor),
                                                           "coverFormat": "2"}, "hashtag", referer)
    items = _ready_items(data.get("itemList"), maxh, headers)
    out = {"tag": info, "items": items, "cursor": int(data.get("cursor") or cursor + 30), "hasMore": bool(data.get("hasMore")),
           "headers": headers}
    CACHE.put(ckey, out, 600 if items else 30)
    return out


def sound(mid, cursor, maxh):
    """A sound: title, author, cover, the sound itself, and a page of the videos that use it (30)."""
    mid = re.sub(r"\D", "", mid or "")
    if not mid:
        raise ValueError("no sound id")
    referer = "https://www.tiktok.com/music/-%s" % mid
    ikey = "soundinfo:%s" % mid
    info = CACHE.get(ikey)
    if info is None:
        data, headers = _web_api("/api/music/detail/", {"musicId": mid}, "music", referer)
        mi = data.get("musicInfo") or {}
        m, st, au = mi.get("music") or {}, mi.get("stats") or {}, mi.get("author") or {}
        info = {"id": mid, "title": m.get("title") or "", "author": m.get("authorName") or au.get("nickname") or "",
                "authorHandle": norm_user(au.get("uniqueId")), "original": bool(m.get("original")),
                "cover": _jpeg([m.get("coverLarge"), m.get("coverMedium"), m.get("coverThumb")]),
                "playUrl": m.get("playUrl") or "", "duration": m.get("duration") or 0,
                "videos": int(st.get("videoCount") or 0), "headers": headers} if m else {}
        CACHE.put(ikey, info, 3600 if info else 60)
    ckey = "sounditems:%s:%d:%d" % (mid, cursor, maxh)
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    data, headers = _web_api("/api/music/item_list/", {"musicID": mid, "count": "30", "cursor": str(cursor), "coverFormat": "2"},
                             "music", referer)
    items = _ready_items(data.get("itemList"), maxh, headers)
    out = {"sound": info or None, "items": items, "cursor": int(data.get("cursor") or cursor + 30),
           "hasMore": bool(data.get("hasMore")), "headers": headers}
    CACHE.put(ckey, out, 600 if items else 30)
    return out


def posts(sec_uid, cursor, maxh, pages=2):
    """A creator's posts, newest first, older than `cursor` (ms; 0 = now): `pages` of TikTok's 15 (it refuses more at
    once). Their creator list answers without a signature (yt-dlp reads it the same way)."""
    sec_uid = re.sub(r"[^A-Za-z0-9_\-]", "", sec_uid or "")
    if not sec_uid:
        raise ValueError("no secUid")
    cursor = cursor or int(time.time() * 1000)
    ckey = "posts:%s:%d:%d" % (sec_uid, cursor // 60000, maxh)
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    items, headers, more = [], {}, True
    for _ in range(max(1, pages)):
        data, headers = _web_api("/api/creator/item_list/", {"secUid": sec_uid, "count": "15", "cursor": str(cursor), "type": "1"},
                                 "user", "https://www.tiktok.com/", sign=False)
        raw = data.get("itemList") or []
        seen = set(i["id"] for i in items)
        items += [i for i in _ready_items(raw, maxh, headers) if i["id"] not in seen]
        last = int((raw[-1].get("createTime") or 0) * 1000) if raw else 0
        more = bool(data.get("hasMorePrevious")) and 0 < last < cursor
        if not more:
            break
        cursor = last
    out = {"items": items, "cursor": cursor if more else 0, "hasMore": more, "headers": headers}
    CACHE.put(ckey, out, 600 if items else 30)
    return out


def profile(name, maxh=1280):
    """A creator's profile: who they are (from their page) and their newest posts, ready to play (yt-dlp's list when
    TikTok's creator list says nothing)."""
    name = norm_user(name)
    if not name:
        raise ValueError("no user")
    ckey = "profile:%s:%d" % (name, maxh)
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    user, sec = {"handle": name}, ""
    try:
        final, html, jar = _web_get("https://www.tiktok.com/@%s" % name)
        ui = (_rehydration(html).get("webapp.user-detail") or {}).get("userInfo") or {}
        u, s = ui.get("user") or {}, ui.get("stats") or {}
        if u:
            sec = u.get("secUid") or ""
            likes = s.get("heartCount") or 0
            if likes < 0 or (s.get("heart") or 0) > likes:      # (heartCount is a 32-bit number and overflows)
                likes = s.get("heart") or 0
            user = {"handle": norm_user(u.get("uniqueId")) or name, "name": u.get("nickname") or "",
                    "bio": u.get("signature") or "", "verified": bool(u.get("verified")),
                    "avatar": _jpeg([u.get("avatarMedium"), u.get("avatarLarger"), u.get("avatarThumb")]),
                    "liveRoom": str(u.get("roomId") or ""), "followers": s.get("followerCount") or 0,
                    "following": s.get("followingCount") or 0, "likes": likes, "videos": s.get("videoCount") or 0,
                    "link": ((u.get("bioLink") or {}).get("link") or "").strip(), "private": bool(u.get("privateAccount")),
                    "secUid": sec}
    except Exception as e:
        sys.stderr.write("profile page of %s failed: %s\n" % (name, e))
    out = {"user": user, "items": [], "cursor": 0, "hasMore": False}
    if sec:
        try:
            page = posts(sec, 0, maxh)
            out.update(items=page["items"], cursor=page["cursor"], hasMore=page["hasMore"], headers=page["headers"])
        except Exception as e:
            sys.stderr.write("profile posts of %s failed: %s\n" % (name, e))
    if not out["items"] and not user.get("private"):
        try:
            out["items"] = user_list(name, 30)
        except Exception as e:
            sys.stderr.write("profile videos of %s failed: %s\n" % (name, e))
            out["error"] = "no videos"
    CACHE.put(ckey, out, 600)
    return out

def live(room):
    """A live room: is it on, and its streams. TikTok hands a visitor FLV (an iOS 6 player cannot read it: the app
    repacks it on the device); an HLS address is passed on too whenever there is one."""
    room = re.sub(r"\D", "", room or "")
    if not room:
        raise ValueError("no room")
    ckey = "live:%s" % room
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    final, body, jar = _web_get("https://webcast.tiktok.com/webcast/room/info/?aid=1988&room_id=%s" % room)
    data = json.loads(body.decode("utf-8", "replace") or "{}").get("data") or {}
    su = data.get("stream_url") or {}
    streams = []
    sd = ((su.get("live_core_sdk_data") or {}).get("pull_data") or {}).get("stream_data") or ""
    try:
        qualities = (json.loads(sd).get("data") or {}) if isinstance(sd, str) and sd else {}
    except ValueError:
        qualities = {}
    for qname, qv in qualities.items():
        main = (qv or {}).get("main") or {}
        try:
            params = json.loads(main.get("sdk_params") or "{}")
        except ValueError:
            params = {}
        if main.get("flv") or main.get("hls"):
            streams.append({"quality": qname, "flv": main.get("flv") or "", "hls": main.get("hls") or "",
                            "vcodec": params.get("VCodec") or "", "resolution": params.get("resolution") or "",
                            "bitrate": params.get("vbitrate") or 0})
    if not streams:
        for qname, u in (su.get("flv_pull_url") or {}).items():
            streams.append({"quality": qname, "flv": u, "hls": "", "vcodec": "", "resolution": "", "bitrate": 0})
        if su.get("hls_pull_url"):
            streams.append({"quality": "hls", "flv": "", "hls": su["hls_pull_url"], "vcodec": "", "resolution": "", "bitrate": 0})
    owner = data.get("owner") or {}
    out = {"room": room, "live": data.get("status") == 2, "title": data.get("title") or "",
           "viewers": data.get("user_count") or 0,
           "cover": _jpeg((data.get("cover") or {}).get("url_list")),
           "owner": {"handle": norm_user(owner.get("display_id")), "name": owner.get("nickname") or "",
                     "avatar": _jpeg((owner.get("avatar_thumb") or {}).get("url_list"))},
           "streams": streams, "headers": _session_headers(jar)}
    CACHE.put(ckey, out, 20)
    return out

def lives(count):
    """Live rooms seen lately among Explore authors; when there are few, a look at a few more topics first."""
    def fresh():
        now = time.time()
        with _LIVE_LOCK:
            return sorted((v for v in _LIVE_SEEN.values() if now - v["seen"] < LIVE_SEEN_TTL), key=lambda v: -v["seen"])
    rooms = fresh()
    if len(rooms) < 6:            # (about one Explore author in seventy is live at a time)
        for cat in random.sample(EXPLORE_TOPICS, 5):
            try:
                discover(cat, 30, 1280)
            except Exception as e:
                sys.stderr.write("lives: topic %s failed: %s\n" % (cat, e))
        rooms = fresh()
    return [dict(r, seen=int(r["seen"])) for r in rooms[:max(1, min(count, 50))]]

def expand(u):
    """Where a TikTok link leads (vm.tiktok.com / vt.tiktok.com short links redirect to the post)."""
    if not re.match(r"^https?://([a-z0-9-]+\.)*tiktok\.com/", u or "", re.I):
        raise ValueError("not a TikTok link")
    final, body, jar = _web_get(u)
    return {"url": final}


# --- Logged-in session management & features -------------------------------

import secrets

SESSIONS_FILE = os.environ.get("TIKIE_SESSIONS", os.path.join(os.path.dirname(os.path.abspath(__file__)), "sessions.json"))
_SESSIONS_LOCK = threading.Lock()
_SESSIONS = {}


def _make_cookie(name, value, domain=".tiktok.com", path="/"):
    return http.cookiejar.Cookie(
        version=0, name=name, value=value, port=None, port_specified=False,
        domain=domain, domain_specified=bool(domain), domain_initial_dot=domain.startswith("."),
        path=path, path_specified=bool(path), secure=True, expires=None,
        discard=False, comment=None, comment_url=None, rest={}, rfc2109=False
    )


def _parse_cookie_input(raw):
    """Parses cookies from JSON list/dict, header string, or Netscape file format."""
    jar = http.cookiejar.CookieJar()
    if isinstance(raw, (bytes, bytearray)):
        raw = raw.decode("utf-8", "replace")
    if isinstance(raw, (dict, list)):
        raw = json.dumps(raw)
    if raw is not None and not isinstance(raw, str):
        raise ValueError("Cookies must be text, an object, or a list")
    raw = (raw or "").strip()
    if not raw:
        return jar

    parsed_json = None
    if (raw.startswith("{") and raw.endswith("}")) or (raw.startswith("[") and raw.endswith("]")):
        try:
            parsed_json = json.loads(raw)
        except Exception:
            parsed_json = None

    if isinstance(parsed_json, list):
        for item in parsed_json:
            if isinstance(item, dict) and "name" in item and "value" in item:
                d = item.get("domain") or ".tiktok.com"
                p = item.get("path") or "/"
                jar.set_cookie(_make_cookie(str(item["name"]), str(item["value"]), d, p))
        return jar
    elif isinstance(parsed_json, dict):
        if "cookies" in parsed_json:
            return _parse_cookie_input(parsed_json["cookies"])
        for k, v in parsed_json.items():
            if isinstance(v, (str, int, float, bool)):
                jar.set_cookie(_make_cookie(str(k), str(v)))
            elif isinstance(v, dict) and "value" in v:
                jar.set_cookie(_make_cookie(str(k), str(v["value"]), v.get("domain", ".tiktok.com"), v.get("path", "/")))
        return jar

    for line in raw.splitlines():
        line = line.strip()
        if line.startswith("#HttpOnly_"):
            line = line[len("#HttpOnly_"):]
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 7:
            domain, _, path, _, _, name, val = parts[:7]
            jar.set_cookie(_make_cookie(name, val, domain, path))
            continue
        for pair in line.split(";"):
            if "=" in pair:
                k, v = pair.split("=", 1)
                k = k.strip()
                v = v.strip()
                if k:
                    jar.set_cookie(_make_cookie(k, v))
    return jar


def _load_sessions():
    global _SESSIONS
    if not os.path.exists(SESSIONS_FILE):
        return
    try:
        with open(SESSIONS_FILE, "r", encoding="utf-8") as f:
            _SESSIONS = json.load(f)
    except Exception as e:
        sys.stderr.write("tikie: failed to load sessions: %s\n" % e)


def _save_sessions():
    try:
        os.makedirs(os.path.dirname(os.path.abspath(SESSIONS_FILE)), exist_ok=True)
        tmp = SESSIONS_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(_SESSIONS, f, indent=2)
        os.replace(tmp, SESSIONS_FILE)
    except Exception as e:
        sys.stderr.write("tikie: failed to save sessions: %s\n" % e)


def _jar_to_list(jar):
    out = []
    for c in jar:
        out.append({
            "name": c.name, "value": c.value, "domain": c.domain,
            "path": c.path, "secure": c.secure, "expires": c.expires
        })
    return out


def _list_to_jar(cookie_list):
    jar = http.cookiejar.CookieJar()
    for item in cookie_list or []:
        jar.set_cookie(_make_cookie(item["name"], item["value"], item.get("domain", ".tiktok.com"), item.get("path", "/")))
    return jar


def _fetch_session_user_info(jar):
    """Contacts TikTok to verify the session and extract logged-in user profile info."""
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    # 1. passport account info
    try:
        p = _web_params("account_info")
        q = urllib.parse.urlencode(p)
        req = urllib.request.Request("https://www.tiktok.com/passport/web/account/info/?" + q,
                                     headers={"User-Agent": UA, "Referer": "https://www.tiktok.com/", "Accept": "application/json"})
        with opener.open(req, timeout=15) as r:
            body = r.read()
        res = json.loads(body.decode("utf-8", "replace") or "{}")
        data = res.get("data") or {}
        user_id = data.get("user_id") or data.get("user_id_str")
        username = data.get("username") or data.get("screen_name")
        if user_id and username:
            return {
                "handle": norm_user(username),
                "name": data.get("screen_name") or username,
                "avatar": data.get("avatar_url") or "",
                "userId": str(user_id),
                "secUid": data.get("sec_user_id") or ""
            }
    except Exception as e:
        sys.stderr.write("passport account probe: %s\n" % e)

    # A cookie name alone does not prove that the session is valid.
    return None


def get_session(token):
    if not token:
        return None
    with _SESSIONS_LOCK:
        sess = _SESSIONS.get(token)
        if sess:
            sess["last_used"] = time.time()
            return sess
    return None


def create_session(cookie_input):
    jar = _parse_cookie_input(cookie_input)
    user_info = _fetch_session_user_info(jar)
    if not user_info:
        raise ValueError("Invalid session or expired cookies")
    token = secrets.token_hex(24)
    now = time.time()
    sess_data = {
        "token": token,
        "cookies": _jar_to_list(jar),
        "user": user_info,
        "created": now,
        "last_used": now,
        "last_validated": now
    }
    with _SESSIONS_LOCK:
        _SESSIONS[token] = sess_data
        _save_sessions()
    return sess_data


def delete_session(token):
    with _SESSIONS_LOCK:
        if token in _SESSIONS:
            del _SESSIONS[token]
            _save_sessions()
            return True
    return False


def logged_in_following(token, count=20, maxh=1280):
    sess = get_session(token)
    if not sess:
        raise ValueError("unauthorized session")
    jar = _list_to_jar(sess["cookies"])
    data, headers = _web_api("/api/feed/following/", {"count": str(count), "source": "following"},
                             "following", "https://www.tiktok.com/following", sign=True, session_jar=jar)
    raw = []
    for it in (data.get("itemList") or data.get("items") or data.get("data") or []):
        if isinstance(it, dict):
            raw.append(it.get("item") or it)
    return _ready_items(raw, maxh, headers), headers


def logged_in_foryou(token, count=20, maxh=1280):
    sess = get_session(token)
    if not sess:
        raise ValueError("unauthorized session")
    jar = _list_to_jar(sess["cookies"])
    data, headers = _web_api("/api/recommend/item_list/", {"count": str(count), "from_page": "fyp"},
                             "fyp", "https://www.tiktok.com/foryou", sign=True, session_jar=jar)
    raw = []
    for it in (data.get("itemList") or data.get("items") or data.get("data") or []):
        if isinstance(it, dict):
            raw.append(it.get("item") or it)
    return _ready_items(raw, maxh, headers), headers


def logged_in_liked(token, count=30, maxh=1280):
    sess = get_session(token)
    if not sess:
        raise ValueError("unauthorized session")
    jar = _list_to_jar(sess["cookies"])
    sec_uid = sess.get("user", {}).get("secUid", "")
    data, headers = _web_api("/api/favorite/item_list/", {"count": str(count), "secUid": sec_uid, "cursor": "0"},
                             "profile", "https://www.tiktok.com/@" + (sess.get("user", {}).get("handle") or "me"),
                             sign=True, session_jar=jar)
    raw = []
    for it in (data.get("itemList") or data.get("items") or data.get("data") or []):
        if isinstance(it, dict):
            raw.append(it.get("item") or it)
    return _ready_items(raw, maxh, headers), headers


def logged_in_notifications(token, count=20):
    sess = get_session(token)
    if not sess:
        raise ValueError("unauthorized session")
    jar = _list_to_jar(sess["cookies"])
    data, _ = _web_api("/api/notice/multi/notice/list/", {"count": str(count)},
                        "notice", "https://www.tiktok.com/messages", sign=True, session_jar=jar)
    items = []
    for n in (data.get("notice_lists") or data.get("notices") or data.get("data") or []):
        nid = str(n.get("id") or n.get("nid") or "")
        ntype = n.get("type") or "notice"
        title = n.get("title") or ""
        content = n.get("content") or n.get("text") or ""
        t = int(n.get("create_time") or time.time())
        from_user = n.get("from_user") or n.get("user") or {}
        u_info = {
            "handle": norm_user(from_user.get("unique_id") or from_user.get("display_id") or ""),
            "name": from_user.get("nickname") or "",
            "avatar": _jpeg((from_user.get("avatar_thumb") or {}).get("url_list"))
        }
        vid = str(n.get("aweme_id") or n.get("item_id") or "")
        items.append({
            "id": nid, "type": ntype, "title": title, "text": content, "time": t,
            "user": u_info, "videoId": vid
        })
    return items


def logged_in_digg(token, aweme_id, digg_type=1):
    sess = get_session(token)
    if not sess:
        raise ValueError("unauthorized session")
    jar = _list_to_jar(sess["cookies"])
    data, _ = _web_api("/api/commit/item/digg/", {"aweme_id": str(aweme_id), "type": str(digg_type)},
                       "item", "https://www.tiktok.com/", sign=True, session_jar=jar)
    return {"ok": data.get("status_code") == 0 and data.get("statusCode", 0) == 0, "raw": data}


def logged_in_follow(token, user_id="", sec_user_id="", follow_type=1):
    sess = get_session(token)
    if not sess:
        raise ValueError("unauthorized session")
    jar = _list_to_jar(sess["cookies"])
    params = {"type": str(follow_type)}
    if user_id:
        params["user_id"] = str(user_id)
    if sec_user_id:
        params["sec_user_id"] = str(sec_user_id)
    data, _ = _web_api("/api/commit/follow/user/", params,
                       "profile", "https://www.tiktok.com/", sign=True, session_jar=jar)
    return {"ok": data.get("status_code") == 0 and data.get("statusCode", 0) == 0, "raw": data}


def logged_in_comment_post(token, aweme_id, text):
    sess = get_session(token)
    if not sess:
        raise ValueError("unauthorized session")
    jar = _list_to_jar(sess["cookies"])
    text = (text or "").strip()
    if not text:
        raise ValueError("empty comment")
    data, _ = _web_api("/api/comment/publish/", {"aweme_id": str(aweme_id), "text": text},
                       "item", "https://www.tiktok.com/", sign=True, session_jar=jar)
    comment_data = data.get("comment") or {}
    cid = str(comment_data.get("cid") or comment_data.get("id") or "")
    return {
        "ok": bool(cid) or data.get("status_code") == 0,
        "cid": cid,
        "text": text,
        "raw": data
    }


# Initialise session store
_load_sessions()

# --- YouTube (added for the Tubie iOS 6 app; everything above is unchanged) ------
# Gives the phone a fresh, playable YouTube stream so it can get past the ~60 s PO-token wall that caps the
# adaptive files when the device fetches them itself. Returns the best progressive MP4 (<=720p, H.264+AAC, plays
# straight away on iOS 6) plus the best adaptive H.264 video and AAC audio (for a later 1080p remux in the app).

YT_UA = ("com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3 like Mac OS X)")

def yt_video_id(s):
    s = (s or "").strip()
    m = re.search(r"(?:v=|/shorts/|/embed/|youtu\.be/|/v/|/live/)([A-Za-z0-9_-]{11})", s)
    if m:
        return m.group(1)
    return s if re.fullmatch(r"[A-Za-z0-9_-]{11}", s) else None

def _ydl_yt(opts):
    # yt-dlp's default player clients return the full H.264 DASH ladder (itags 133-137 etc.) with direct URLs;
    # forcing ios/web cut it down to the 360p progressive only, so leave the clients at their defaults.
    base = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": True,
        # a permissive selector so extract_info never fails on "no requested format" (we read info["formats"]
        # ourselves anyway, and the container has no ffmpeg to merge a video+audio pick)
        "format": "bv*+ba/b/bv*/ba",
        "ignore_no_formats_error": True,
    }
    base.update(opts)
    return yt_dlp.YoutubeDL(base)

def _yt_pick(fmts, want):
    """want: 'prog' (video+audio mp4 <=720), 'video' (avc1 video-only <=1080), 'audio' (m4a audio-only)."""
    out = []
    for f in fmts:
        if not f.get("url"):
            continue
        va = f.get("vcodec") not in (None, "none")
        aa = f.get("acodec") not in (None, "none")
        vc = f.get("vcodec") or ""
        h = f.get("height") or 0
        if want == "prog":
            if not (va and aa and (f.get("ext") == "mp4") and vc.startswith("avc") and (h == 0 or h <= 720)):
                continue
        elif want == "video":
            if not (va and not aa and vc.startswith("avc") and (h == 0 or h <= 1080)):
                continue
        elif want == "audio":
            ac = f.get("acodec") or ""
            if not (aa and not va and (ac.startswith("mp4a") or f.get("ext") == "m4a")):
                continue
        out.append(f)
    if want == "audio":
        out.sort(key=lambda f: (f.get("abr") or f.get("tbr") or 0))
    else:
        out.sort(key=lambda f: ((f.get("height") or 0), (f.get("tbr") or 0)))
    return out[-1] if out else None

def _yt_headers(info, f):
    h = {"User-Agent": YT_UA}
    if isinstance(info.get("http_headers"), dict):
        h.update(info["http_headers"])
    if isinstance(f.get("http_headers"), dict):
        h.update(f["http_headers"])
    return h

def resolve_yt(ref):
    vid = yt_video_id(ref)
    if not vid:
        raise ValueError("no youtube video id")
    ckey = "yt:%s" % vid
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    url = "https://www.youtube.com/watch?v=%s" % vid
    with _YDL_LOCK, _ydl_yt({}) as ydl:
        info = ydl.extract_info(url, download=False)
    fmts = info.get("formats") or []
    # A map itag -> fresh direct URL for every format served straight over https (the DASH ladder 133-137 etc. and
    # the audio 139/140), skipping HLS. Tubie keeps the sidx byte ranges it already got from its own InnerTube for
    # each itag and just swaps in these URLs, so the proxy can remux the whole video (no 60 s PO-token wall).
    formats = {}
    audio_pick = {}   # base itag -> (score, url): for dubbed videos keep only the original/default track
    for f in fmts:
        u = f.get("url")
        if not u or (f.get("protocol") or "") not in ("https", "http"):
            continue   # skip m3u8/HLS; we want the directly-ranged files
        fid = str(f.get("format_id") or "")
        base = fid.split("-")[0]   # multi-language audio comes as "140-0".."140-19"
        if not base.isdigit():
            continue
        is_audio = f.get("acodec") not in (None, "none") and f.get("vcodec") in (None, "none")
        if is_audio and "-" in fid:
            # the app's sidx ranges are for the ORIGINAL audio, so pick the track yt-dlp marks default/original
            score = f.get("language_preference") or -1
            note = (f.get("format_note") or "").lower()
            if "default" in note or "original" in note:
                score += 1000
            if base not in audio_pick or score > audio_pick[base][0]:
                audio_pick[base] = (score, u)
        else:
            formats[base] = u
    for base, (score, u) in audio_pick.items():
        formats.setdefault(base, u)
    prog = _yt_pick(fmts, "prog")
    out = {
        "id": vid,
        "title": info.get("title") or "",
        "duration": info.get("duration") or 0,
        "isLive": bool(info.get("is_live")),
        "formats": formats,
    }
    if prog:
        out["playUrl"] = prog.get("url")
        out["playHeight"] = prog.get("height") or 0
        out["playItag"] = str(prog.get("format_id") or "")
    CACHE.put(ckey, out, 3600)   # googlevideo URLs last ~6 h; refresh well before that
    return out

# --- HTTP ----------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "tikie/1.0"

    def _send_json(self, obj, status=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    @staticmethod
    def _int(q, name, default=0):
        try:
            return max(0, int(q.get(name, [str(default)])[0] or default))
        except ValueError:
            return default

    @staticmethod
    def _maxh(q):
        return max(240, min(Handler._int(q, "maxh", 1280) or 1280, 4096))

    def _authorized(self, q):
        if not KEY:
            return True
        return q.get("k", [""])[0] == KEY or self.headers.get("X-Tikie-Key", "") == KEY

    def log_message(self, fmt, *args):
        sys.stderr.write("tikie %s - %s\n" % (self.address_string(), fmt % args))

    def _get_session_token(self, q):
        return (self.headers.get("X-Tikie-Session") or q.get("session", [""])[0] or q.get("t", [""])[0] or "").strip()

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        q = urllib.parse.parse_qs(parsed.query)
        if path == "/health" or path == "/yt/health":
            return self._send_json({"ok": True, "ytdlp": getattr(yt_dlp.version, "__version__", "?")})
        if not self._authorized(q):
            return self._send_json({"error": "unauthorized"}, 401)
        try:
            if path == "/session/validate":
                token = self._get_session_token(q)
                sess = get_session(token)
                if not sess:
                    return self._send_json({"ok": False, "valid": False, "error": "session expired"}, 401)
                return self._send_json({"ok": True, "valid": True, "user": sess["user"]})
            if path == "/session/delete":
                token = self._get_session_token(q)
                delete_session(token)
                return self._send_json({"ok": True})
            if path == "/me":
                token = self._get_session_token(q)
                sess = get_session(token)
                if not sess:
                    return self._send_json({"error": "unauthorized session"}, 401)
                return self._send_json({"user": sess["user"]})
            if path == "/following":
                token = self._get_session_token(q)
                items, headers = logged_in_following(token, self._int(q, "count", 20), self._maxh(q))
                return self._send_json({"items": items, "headers": headers})
            if path == "/foryou":
                token = self._get_session_token(q)
                items, headers = logged_in_foryou(token, self._int(q, "count", 20), self._maxh(q))
                return self._send_json({"items": items, "headers": headers})
            if path == "/liked":
                token = self._get_session_token(q)
                items, headers = logged_in_liked(token, self._int(q, "count", 30), self._maxh(q))
                return self._send_json({"items": items, "headers": headers})
            if path == "/notifications":
                token = self._get_session_token(q)
                items = logged_in_notifications(token, self._int(q, "count", 20))
                return self._send_json({"items": items})
            if path == "/digg":
                token = self._get_session_token(q)
                return self._send_json(logged_in_digg(token, q.get("id", [""])[0] or q.get("aweme_id", [""])[0], self._int(q, "type", 1)))
            if path == "/follow":
                token = self._get_session_token(q)
                return self._send_json(logged_in_follow(token, q.get("user_id", [""])[0], q.get("sec", [""])[0], self._int(q, "type", 1)))
            if path == "/comment_post":
                token = self._get_session_token(q)
                return self._send_json(logged_in_comment_post(token, q.get("id", [""])[0] or q.get("aweme_id", [""])[0], q.get("text", [""])[0]))
            if path == "/discover":
                try:
                    cat = int(q.get("cat", ["120"])[0])
                    count = int(q.get("count", ["20"])[0])
                    maxh = int(q.get("maxh", ["1280"])[0])
                except ValueError:
                    raise ValueError("cat, count and maxh must be numbers")
                items, headers = discover(cat, count, max(240, min(maxh, 4096)))
                return self._send_json({"items": items, "headers": headers, "category": cat})
            if path == "/user":
                return self._send_json({"items": user_list(q.get("name", [""])[0], int(q.get("count", ["30"])[0]))})
            if path == "/resolve":
                ref = q.get("id", [""])[0] or q.get("url", [""])[0]
                # what the device can show; app builds that send nothing get the iOS 6 defaults
                vcodec = (q.get("vcodec", ["h264"])[0] or "h264").lower()
                try:
                    maxh = int(q.get("maxh", ["1280"])[0])
                except ValueError:
                    maxh = 1280
                maxh = max(240, min(maxh, 4096))
                return self._send_json(resolve(ref, q.get("user", [None])[0], vcodec, maxh))
            if path == "/yt/resolve":
                return self._send_json(resolve_yt(q.get("id", [""])[0] or q.get("url", [""])[0]))
            if path == "/comments":
                ref = q.get("id", [""])[0] or q.get("url", [""])[0]
                return self._send_json({"items": comments(ref, int(q.get("count", ["40"])[0]))})
            if path == "/replies":
                return self._send_json({"items": replies(q.get("id", [""])[0], q.get("cid", [""])[0], int(q.get("count", ["20"])[0]))})
            if path == "/profile":
                return self._send_json(profile(q.get("name", [""])[0], self._maxh(q)))
            if path == "/posts":
                return self._send_json(posts(q.get("sec", [""])[0], self._int(q, "cursor"), self._maxh(q)))
            if path == "/search":
                return self._send_json(search(q.get("q", [""])[0], self._int(q, "offset"), self._maxh(q)))
            if path == "/suggest":
                return self._send_json({"items": suggest(q.get("q", [""])[0])})
            if path == "/tag":
                return self._send_json(tag(q.get("name", [""])[0], self._int(q, "cursor"), self._maxh(q)))
            if path == "/sound":
                return self._send_json(sound(q.get("id", [""])[0], self._int(q, "cursor"), self._maxh(q)))
            if path == "/live":
                return self._send_json(live(q.get("room", [""])[0]))
            if path == "/lives":
                return self._send_json({"items": lives(int(q.get("count", ["20"])[0]))})
            if path == "/expand":
                return self._send_json(expand(q.get("u", [""])[0] or q.get("url", [""])[0]))
            if path == "/proxy":
                return self._proxy(q.get("u", [""])[0])
        except ValueError as e:
            return self._send_json({"error": str(e)}, 400)
        except Exception as e:
            sys.stderr.write("tikie error on %s: %s\n" % (path, e))
            return self._send_json({"error": "upstream failed", "detail": str(e)[:200]}, 502)
        return self._send_json({"error": "not found"}, 404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        q = urllib.parse.parse_qs(parsed.query)
        if not self._authorized(q):
            return self._send_json({"error": "unauthorized"}, 401)
        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            return self._send_json({"error": "invalid content length"}, 400)
        if length < 0 or length > 1024 * 1024:
            return self._send_json({"error": "request body too large"}, 413)
        raw_body = self.rfile.read(length) if length > 0 else b""
        body_str = raw_body.decode("utf-8", "replace")
        body_json = {}
        try:
            body_json = json.loads(body_str) if body_str.strip() else {}
        except Exception:
            body_json = {}

        if not isinstance(body_json, dict):
            return self._send_json({"error": "expected a JSON object"}, 400)
        try:
            if path == "/session/create":
                cookie_data = body_json.get("cookies", body_str)
                sess = create_session(cookie_data)
                return self._send_json({"ok": True, "token": sess["token"], "user": sess["user"]})
            if path == "/session/delete":
                token = self._get_session_token(q) or body_json.get("token", "")
                delete_session(token)
                return self._send_json({"ok": True})
            if path == "/digg":
                token = self._get_session_token(q) or body_json.get("token", "")
                aweme_id = body_json.get("aweme_id") or body_json.get("id") or q.get("id", [""])[0]
                dtype = body_json.get("type", q.get("type", [1])[0])
                return self._send_json(logged_in_digg(token, aweme_id, int(dtype)))
            if path == "/follow":
                token = self._get_session_token(q) or body_json.get("token", "")
                user_id = body_json.get("user_id") or q.get("user_id", [""])[0]
                sec_uid = body_json.get("sec_user_id") or body_json.get("sec") or q.get("sec", [""])[0]
                ftype = body_json.get("type", q.get("type", [1])[0])
                return self._send_json(logged_in_follow(token, user_id, sec_uid, int(ftype)))
            if path == "/comment_post":
                token = self._get_session_token(q) or body_json.get("token", "")
                aweme_id = body_json.get("aweme_id") or body_json.get("id") or q.get("id", [""])[0]
                text = body_json.get("text") or q.get("text", [""])[0]
                return self._send_json(logged_in_comment_post(token, aweme_id, text))
        except ValueError as e:
            return self._send_json({"error": str(e)}, 400)
        except Exception as e:
            sys.stderr.write("tikie POST error on %s: %s\n" % (path, e))
            return self._send_json({"error": "upstream failed", "detail": str(e)[:200]}, 502)
        return self._send_json({"error": "not found"}, 404)

    def _proxy(self, u):
        if not u or not re.match(r"^https://", u):
            return self._send_json({"error": "bad url"}, 400)
        host = urllib.parse.urlparse(u).hostname or ""
        if not CDN_HOST_RE.search(host):
            return self._send_json({"error": "host not allowed"}, 403)
        hdrs = CACHE.get("hdr:" + u) or {"User-Agent": UA, "Referer": "https://www.tiktok.com/"}
        req = urllib.request.Request(u, headers=dict(hdrs))
        rng = self.headers.get("Range")
        if rng:
            req.add_header("Range", rng)
        try:
            up = urllib.request.urlopen(req, timeout=20)
        except Exception as e:
            return self._send_json({"error": "fetch failed", "detail": str(e)[:200]}, 502)
        self.send_response(up.status)
        for h in ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges"):
            v = up.headers.get(h)
            if v:
                self.send_header(h, v)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        if self.command == "HEAD":
            up.close()
            return
        try:
            while True:
                chunk = up.read(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            up.close()


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    sys.stderr.write("tikie helper listening on :%d (key %s)\n" % (PORT, "set" if KEY else "off"))
    server.serve_forever()


if __name__ == "__main__":
    main()
