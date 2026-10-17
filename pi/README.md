# TikTak helper (Raspberry Pi)

The small service the iOS 6 app (TikTak) talks to; the service itself is called `tikie` (the app's first name).
It finds public TikTok videos - TikTok's logged-out web pages and `yt-dlp` - and returns tiny JSON. Video normally
streams straight from TikTok's CDN to the device; only `/proxy` moves the bytes through the Pi (fallback away from
home). Read-only: no login, no posting. The same service also answers the Tubie app (`/yt/...`).

## Run

```sh
docker compose up -d --build        # builds the image, starts tikie on :8730
curl http://<pi>:8730/health
curl "http://<pi>:8730/discover?cat=104&count=10"
```

## Keep it working

TikTok changes often; `yt-dlp` is the maintained piece. When something stops resolving:

```sh
docker compose build --no-cache && docker compose up -d     # rebuild with the latest yt-dlp
```

## Exposing beyond the LAN

Set `TIKIE_KEY` in `docker-compose.yml`; the app must then send `?k=<key>` (or the `X-Tikie-Key` header). Point
your existing nginx/cloudflared at `http://127.0.0.1:8730`. The app's "server" setting takes the base URL (and key).

## Endpoints

| path | returns |
|------|---------|
| `/health` | `{ok, ytdlp}` |
| `/discover?cat=&count=&maxh=` | a fresh batch of an Explore topic (100-119): items ready to play (H.264 up to `maxh`), with the topic, hashtags, sound, language and age the app learns from, plus the `headers` the CDN wants |
| `/user?name=&count=` | a creator's recent videos |
| `/resolve?id=&user=&vcodec=&maxh=` | one post ready to play: `playUrl` and `headers`, or a photo post's `images` and sound |
| `/comments?id=&count=` | `{items:[{cid,author,authorName,text,likes,replies,pinned,time}]}` |
| `/replies?id=&cid=&count=` | the replies to one comment |
| `/profile?name=` | `{user:{handle,name,bio,avatar,verified,liveRoom,followers,likes,videos}, items}` |
| `/live?room=` | a live room: `live`, title, viewers, owner, `streams` (FLV/HLS addresses by quality and codec), `headers` |
| `/lives?count=` | live rooms seen lately among Explore authors (TikTok lists live rooms only to signed-in apps) |
| `/expand?u=` | where a short link (vm./vt.tiktok.com, /t/...) leads |
| `/proxy?u=` | the video bytes (TikTok CDN hosts only), Range supported |
| `/yt/resolve?id=`, `/yt/health` | for Tubie (YouTube) |
