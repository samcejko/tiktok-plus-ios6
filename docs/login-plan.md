> Historical proposal from 2026-10-16. Superseded by the direct-device implementation on 2026-10-24; see `direct-client.md`.

# TikTak — Sign-in & logged-in features: implementation plan

Status: proposal / not started · Written 2026-10-16

This plan is about adding **account sign-in** to TikTak and the features that need it
(your own For You, your own profile, the accounts you follow, notifications, and
optionally like / comment / follow). It was written after reviewing the
`atniker/legacy-ios-tiktok-client` project and the current TikTak codebase.

The short version: sign-in is doable and would close the one gap people name against us,
but TikTok has made logged-in access harder than it was, so we do it **through the Pi
helper** (never on-device), we **validate the signing situation before we build any UI**,
and we keep our stability advantage by not copying the competitor's heavy
download-everything playback.

---

## 1. What people are asking for

Feedback is: the atniker client is "better" because it has sign-in (real personal For You,
notifications, own profile), but TikTak is "more stable". We want sign-in **without**
giving up the stability that is our whole selling point.

So the target is: **match their logged-in feature set, keep our streaming/playback and
navigation as they are.**

---

## 2. What the atniker client actually does (and what we borrow / avoid)

atniker is **C# / Xamarin (MonoTouch)**, calls labelled "iOS 3 client". It does **not**
talk to TikTok from the device at all — it talks to **one public server owned by the
author** (`http://miriznik-...:33543/`, plain HTTP) which does every logged-in call.

Sign-in flow (from `Atnik/TikTok.cs`, `Views/WelcomeViewController.cs`):

1. User puts a cookies file (`ttcookies.json`) into the app's Documents via iTunes File
   Sharing.
2. App base64-encodes the file contents and `POST`s it to the author's server
   (`get_session`).
3. Server logs into the account, returns a `session` id + a `download_data`
   (headers + cookies) blob the app uses to pull video bytes from the CDN, plus the
   profile.
4. On next launch the app calls `validate_session/<id>`; on `403` it shows "session
   expired" and restarts setup.

Logged-in surface they expose: `get_trending` (personal FYP), `get_notifications`,
`get_profile`, `get_comments`, `get_video`, `get_avatar` (server-proxied avatars).

### Borrow (the good ideas)

- **Session acquired by importing the user's own TikTok cookies**, then the *server* (our
  Pi) does the logged-in calls. This matches TikTak's existing "everything goes through
  the helper" architecture exactly — see §4.
- **`validate_session` on launch** + a clean "session expired → re-auth" path. (atniker
  does this but then calls `Environment.Exit(0)` — we do it gracefully.)
- **Server-proxied avatars as a fallback** when a direct image load fails — we already
  have `TKImageLoader`; add an "assisted" path only if logged-in avatars need cookies.
- **A Notifications screen and an own-profile screen** — UI we don't have yet.

### Do NOT borrow (these are why it's unstable / unsafe)

- **Plain HTTP to a public third-party server** and `ServerCertificateValidationCallback =>
  true` (accepts any TLS cert). We use our own Pi over TLS 1.2 with a pinned CA bundle.
- **Sending the whole cookie file to someone else's server.** The session stays on *our*
  Pi, per-user, and is never broadcast to clients (see §7).
- **"Warmboot" = download each whole MP4 to disk before playing** (`Atnik/Warmboot.cs`).
  This is a big part of their instability (disk/memory, cancel races). TikTak already
  streams through `TKMediaProxy` + `AVPlayer` and starts in ~1 call — keep it.
- Static-everything globals and `Environment.Exit(0)` on error.

---

## 3. Why there is no "tap to log in" button on iOS 6

Researched 2026-10-16. Two hard blockers:

- **Native / QR login is refused for non-browser clients.** Another iOS 6 TikTok client
  (RetroTiktok, iPhone 4S / iOS 6.1.3, ObjC + mbedTLS — same stack as us) implemented the
  web QR login. `get_qrcode` works, but the scan-confirm step always fails for a
  non-browser client, from both a datacenter and a home iPhone, even with signing added.
  Author's conclusion: TikTok will not hand a session to a non-browser client. That PR was
  closed as "won't merge, kept as a record".
- **Logged-in web endpoints now want browser-only signatures.** Beyond `X-Bogus` (which
  our Pi already fakes), many endpoints as of 2025/2026 also require a browser-minted
  `msToken` cookie **and** a newer `X-Gnarly` signature derived from in-browser JS
  fingerprinting. Pure offline reimplementations exist but are pinned to a specific SDK
  version and break on updates.

**Consequence:** the only realistic way in is the user signing into their own TikTok **in a
real browser** and us importing that session. Everything after that is a feasibility
question we must test before building (see §5).

---

## 4. Recommended architecture

Keep the existing shape: **device → Pi helper → TikTok.** Add a *per-user session* on the
Pi. The device never holds TikTok cookies beyond the moment of import, never signs
requests, never calls TikTok logged-in endpoints directly.

```
  [TikTak app]  --(token t, over TLS)-->  [Pi helper]  --(sessionid + X-Bogus/…)-->  [TikTok]
       |                                       |
   Keychain: t  (random handle)          session store: t -> {cookies}  (per user, private)
```

- On import, the device sends the user's cookies to the Pi **once**, the Pi stores them
  under a **random opaque token `t`**, and returns `t`. The device keeps only `t` (in the
  Keychain), never the cookies.
- Every logged-in call is an existing-style helper GET plus `t` (as the `X-Tikie-Session`
  header, *not* a query param, so it doesn't land in logs).
- Logged-out TikTak keeps working exactly as today; logged-in is strictly additive.

Why not on-device: the device has no cookie jar, no signer, and can't do `X-Gnarly`;
`TKCommon.h:6` makes any post-iOS-6 API a compile error; and we'd duplicate the Pi's
session handling. This is the lowest-risk path and fits what's already there.

---

## 5. Phase 0 — feasibility spike (DO THIS FIRST, before any UI)

We will not know which logged-in features are even possible until we test real endpoints
with a real session. **This phase is a throwaway probe script on the Pi**, run against a
**secondary/throwaway TikTok account** we control, human-paced.

For each candidate endpoint, record: works with cookies only? needs `X-Bogus`? needs
`X-Gnarly`/`msToken` (= browser-only = drop it)? returns real personal data?

Candidates, in priority order:

1. **Own profile / own user info** (lowest risk, almost certainly works) — proves the
   session is valid.
2. **"Following" feed** (videos from creators the user follows).
3. **Personalized recommend / For You** for the logged-in user.
4. **Notifications / activity.**
5. **Liked / favorited list.**
6. (Phase 3 only) **like (digg), follow, post comment** — writes.

Output of Phase 0: a short table in this doc of "green / needs-signing / impossible". The
rest of the plan's scope is then trimmed to the green rows. **If recommend/following need
`X-Gnarly`, we ship sign-in with own-profile + notifications + liked-list only, and keep
the current taste-based For You as the default feed** — still a real win and still stable.

Ban-risk note: these are grey-area endpoints; the feasibility account may get flagged.
That's expected and is the point of using a throwaway. See §12.

---

## 6. How the user signs in (login method)

All three options end the same way: the user's own cookies reach the Pi once. They differ
only in how the cookies get from "logged into TikTok in a browser" into TikTak. **Pick one
in §14.** Recommended: **A**.

- **A. File drop via iFile/Filza/iTunes (recommended).** User logs into tiktok.com in any
  browser, saves a small `ttsession.json` (a couple of cookie values) into the app's
  `Documents/`. The app detects it on the sign-in screen, imports it to the Pi, then
  **deletes the file**. Pros: no change to other apps; jailbreak users already use Filza;
  this is the proven atniker path but cleaner. Cons: user has to fetch cookies from a
  browser (same bar as the competitor).
- **B. Hand-off from Surfari.** Surfari already does cookie login and can open `tikie:`
  URLs. Surfari signs into tiktok.com and hands the session to TikTak. Pros: most "native",
  one ecosystem. Cons: **needs changes to the Surfari repo, which is hands-off without your
  OK**, and passing a session through a URL scheme is a fixation risk (any app/page can
  invoke the scheme) — would need a one-time nonce handshake, not a raw cookie in the URL.
- **C. Paste the session string** into a text field on the sign-in screen (reuse
  `TKTheme textFieldBackgroundImage`, unused today). Pros: no files. Cons: clumsy on an
  iPad 2 soft keyboard; easy to paste the wrong thing.

Security rules regardless of method:
- Never accept a session through the `tiktak:`/`tikie:` URL scheme as a plain value (the
  debug map already warns: any app/web page can open it). Import is file/field/nonce only.
- The sign-in screen states plainly: this signs into **your own** account; use a secondary
  account; we never post without you asking.

---

## 7. Session storage & security

Device:
- Store only the opaque token `t` in the Keychain (`TKKeychain`, service
  `com.samcejko.tikie`), key e.g. `tikie.session`. Note the keychain has a **plaintext
  NSUserDefaults fallback** (`kc.<key>`) if `SecItemAdd` fails — acceptable for an opaque
  handle, **not** for raw cookies, which is another reason cookies never live on the
  device.
- A `signedIn` computed flag = token present.

Pi:
- Per-user session store keyed by `t` → `{cookies, created, lastValidated}`, written to a
  file the container can persist. Separate from the global logged-out `_web_session` jar.
- **Critical:** `_session_headers(jar)` currently sends *every* tiktok cookie back to
  clients as `headers` for CDN replay. A logged-in `sessionid` must **never** go into that
  path. Logged-in CDN pulls either (a) don't need the sessionid (test in Phase 0) or (b)
  are proxied by the Pi's `/proxy`. Add a test/assert that `sessionid`/`sid_tt` never
  appear in any `headers` blob returned to a client.
- `TIKIE_KEY` auth stays on; add rate limiting per `t`.

---

## 8. Phased feature rollout

**Phase 1 — plumbing (no visible features yet).**
- Pi: `/session/create` (POST cookies → token), `/session/validate`, `/session/delete`;
  per-user store; the `sessionid`-never-leaks guard.
- Device: sign-in screen, import (chosen method), token in Keychain, validate on launch,
  sign-out, "session expired" banner → re-auth (no crash, no exit).

**Phase 2 — read-only logged-in (only the green rows from Phase 0).**
- Own profile screen (reuse `TKProfileViewController`, pass own handle).
- "Following" feed and/or personal For You, plugged in as an alternate feed source
  (see §9).
- Liked / favorited list (a `TKGridViewController`).
- Notifications screen (new, modelled on atniker's, built with our theme + `TKHTTP`).

**Phase 3 — writes (opt-in, off by default, clearly warned).**
- Like / unlike (digg), follow / unfollow, post a comment.
- These go against TikTak's read-only ethos and raise ban risk, so: a Settings switch
  "Allow actions on my account (experimental)", default off; a one-time warning; all
  gated behind the same human-pace guard as auto-advance. Only build the ones Phase 0
  showed are feasible.

---

## 9. Device code changes (concrete)

New files (each new `src/<dir>` also needs a `-I` in the Makefile, per `Makefile:33`):
- `src/UI/TKLoginViewController.{h,m}` — the sign-in screen. Copy the look of
  `TKTopicsViewController.m` (page background + grain, embossed title, accent button).
  Use `TKTheme textFieldBackgroundImage` / `cardBackgroundImage` if method C.
- `src/UI/TKNotificationsViewController.{h,m}` — grouped/plain table, `TKHTTP` for the
  avatar loads, our theme.
- `src/TikTok/TKSession.{h,m}` — tiny: holds token, `signedIn`, create/validate/delete via
  the Pi, posts a `TKSessionDidChangeNotification`.

Edited:
- `TKTikTok.{h,m}` — add `sessionValidate`, `myProfile`, `followingFeed:`,
  `personalFeed:`, `likedBy:`, `notifications:` (each a helper GET + the session header).
  All route through the Pi like every other call. The `fetchText:` direct-CDN pattern is
  the only exception and stays as is.
- `TKSettingsViewController.m` — add a **SecAccount** section right after `SecServer`:
  signed out → one "Sign in" row (push `TKLoginViewController` like the Feed rows at
  m:152-154); signed in → avatar+handle, "My profile", "Sign out" (red, styled like
  m:111). Reword the "No login, no posting" About footer (m:66, and `cs.lproj:99`).
- `TKFeedViewController.m` gear menu (`openMenu`, m:715-745) — when signed in, add
  "For You / Following" switch, "Notifications", "My profile". Remember the handler
  switches on button index, so renumber carefully.
- Feed source seam — introduce a `TKFeedSource` protocol over the surface
  `TKFeedViewController` already uses (`videos`, `loading`, `reloadWithCompletion:`,
  `ensureAhead:by:`, the `note…` methods; `TKFeed.h:11-24`), and pick the source in
  `-init` (`TKFeedViewController.m:88`): signed-in personal vs the current `TKFeed`.
  **Server-ordered personal items must skip `TKFeed takeNext`'s re-ranking** — show them
  in the order TikTok gave. The Following feed can reuse the existing fixed-list mode
  (`openVideos:startIndex:title:loadMore:`).
- `TKProfileViewController.m` — if Phase 3 follow ships, a Follow button fits next to the
  "Watch live" button (`layoutForWidth:` m:157-160). Update the "No following" header
  comment (`TKProfileViewController.h:5`).
- Phase 3 comment composer — `TKCommentsViewController` is read-only with no input field
  anywhere in the app; a composer needs a footer bar / container controller (new work,
  not a tweak).

Keep: `TKMediaProxy` streaming (do **not** adopt file-download warmboot), the page
navigation stack, the taste engine (as the logged-out default feed).

---

## 10. Pi helper changes (concrete)

Current helper has **no `do_POST`** (GET/HEAD only) and one global logged-out session.
Add, placed **before line 902** or between 1018 and `class Handler` (the `/yt` block
902-1018 and its routing must not be touched — it's shared with Tubie):

- `do_POST` support (small) for `/session/create` only; everything else stays GET.
- `/session/create` (POST): accept the user's cookies, store under a new random token,
  return the token. Validate the session immediately; reject if invalid.
- `/session/validate?…` (header `X-Tikie-Session`): cheap own-profile call; `403`-style
  body on expiry.
- `/session/delete`: drop the token.
- `/me`, `/following`, `/foryou`, `/liked`, `/notifications` — the logged-in reads that
  passed Phase 0, each reading the session from `X-Tikie-Session`, reusing the existing
  `x_bogus` signer and per-user cookie jar.
- Phase 3 writes: `/digg`, `/follow`, `/comment_post` — only if feasible; rate-limited.
- Keep `X-Bogus` signing (`x_bogus`, server m:576-594). If Phase 0 shows `X-Gnarly` is
  required, document it here and descope those endpoints rather than shipping a fragile
  signer.
- Deploy via the existing md5-compare / `.next` / dry-run / `.bak` / `docker cp` /
  `docker restart tikie` ritual, and re-verify `/yt/resolve?id=dQw4w9WgXcQ` every time.

---

## 11. Localization, build, debug

- Every new `L(@"…")` string needs a `cs.lproj` entry; run `tools/check-strings.ps1`
  (it only sees literal `L(@"…")`). English is the key; Czech in `cs.lproj`.
- Build: new code must compile for **both** armv7 (9.3 SDK, iOS 6) and arm64 (16.5 SDK,
  iOS 14) — mind `NSInteger` widths; no post-iOS-6 API outside a `TKModern`-style guarded
  file; no `NSURL*` loaders (use `TKHTTP`). No CoreImage, so no on-device QR generation
  (not needed anyway).
- Debug commands live in `TKAppDelegate.m:94-277`. Add `signin`/`signout`/`session`
  **behind the debug gate** for testing; **never** import a real session through the URL
  scheme.

---

## 12. Ban-risk & ethics guardrails

- These are unofficial, grey-area endpoints. Risk of account flags is real. **Default to
  read-only**; writes are opt-in and warned.
- Tell the user, in the sign-in screen and the docs, to use a **secondary account**.
- Keep every automated action human-paced and behind the existing unattended guard
  (`TKAutoAdvancesThatTeach`/`Max`, `viewerIsHere`); no background bursts.
- The session is the user's own credential: stored per-user on the Pi, never shown, never
  logged, never sent to any client, deletable via Sign out.
- Do not add a "log into any account" / multi-account harvesting path. One signed-in user,
  their own account.

---

## 13. Suggested order of work

1. **Phase 0 spike** on the Pi with a throwaway account → fill in the feasibility table.
2. Pi session endpoints + the sessionid-never-leaks guard + tests.
3. Device `TKSession` + sign-in screen + Settings account section + validate-on-launch.
4. Own profile + notifications (the safe wins).
5. Following / personal feed via the `TKFeedSource` seam (only if green).
6. Liked list.
7. (Optional, later) Phase 3 writes behind the experimental switch.
8. Reword the "no login" copy across README / CONTRIBUTING / settings footer, bump
   `control`/`CHANGELOG`.

---

## 14. Open decisions (need your call)

1. **Login method** — A file drop (recommended) / B Surfari hand-off (touches the Surfari
   repo) / C paste the session string.
2. **Writes in scope?** Read-only logged-in only (own FYP, profile, notifications), or also
   like/comment/follow (Phase 3, higher ban risk, against the current read-only ethos)?
3. **Fallback if signing blocks the personal feed:** ship sign-in with profile +
   notifications + liked list and keep the taste-based For You as default — OK?
