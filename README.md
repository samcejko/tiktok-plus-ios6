# TikTak - TikTok on iOS 6

An unofficial TikTok **viewer** for jailbroken iOS 6.x (iPad 2 / iPhone 4S era) and, as a second build of the same
sources, for 64-bit devices with iOS 14–17 (iPhone X and newer: rootless jailbreaks and TrollStore), in English and Czech. A vertical,
full-screen "For You" feed that tries videos from all of TikTok's topics and learns on the device what you like -
what you watch to the end, save or skip; no following, no preset creators (at the first start you can pick a few
topics to give it a head start). You can search TikTok, open hashtags and sounds, watch videos and photo posts with
TikTok's captions, live streams, read comments and their replies, look at a creator's page and save videos for
yourself. Read-only: no login, no likes, no posting.

TikTak is not affiliated with, endorsed by or associated with TikTok or ByteDance. It only reads public content.
(Its first name was Tikie, which still shows inside: the bundle, the bundle id and the `tikie:` scheme.)

## How it works (and why it needs your own server)

TikTok's app API is locked behind request signing that cannot be reproduced on iOS 6, so TikTak does not talk to
TikTok directly for the lists. Instead a tiny helper (the `tikie` service) runs on your own machine (a Raspberry Pi
is perfect) and uses the maintained `yt-dlp` and TikTok's public web pages to find videos and fresh direct URLs.
The app asks the helper for a little JSON; the **video itself streams straight from TikTok's CDN to the device**
through TikTak's own TLS layer (iOS 6 cannot talk to modern servers otherwise). Away from home, or if a direct URL
is refused, the helper can also stream the bytes itself. Live streams come as FLV, which the iOS 6 player cannot
open: TikTak repacks them on the device into a live HLS playlist (nothing is re-encoded, and the Pi does not carry
the video).

So: one small service on your server, and the app is a thin, private client. When TikTok changes something, you
update `yt-dlp` on the server - the app does not need rebuilding.

See `pi/README.md` to run the helper (Docker). Then in the app: Settings - the gear on the feed - set the server
address (e.g. `https://ytdlp.samcejko.eu`) and, if you set one, the key. The feed fills up by itself.

Links: `tiktak:open?url=<a TikTok link>` (or `tikie:...`) opens a video, photo post, profile, hashtag, sound or
live stream (Surfari offers it for tiktok.com links), and so does "Open a link" in the gear menu. Also
`tiktak:search?q=<words>`, `tiktak:tag/<hashtag>` and `tiktak:sound/<id>`. Web links in captions, comments and bios
are tappable: a TikTok link opens in TikTak, a YouTube, Twitch or Kick link in Tubie, Twitcher or Kicker when that
app is installed, anything else in Safari or Surfari (iOS 6 asks which; newer iOS opens Safari).

## Installing on the device

The easy way: add the repository `http://repo.samcejko.eu/` in Cydia (Sources → Edit → Add), Sileo, Zebra or Installer
and install TikTak from there; updates then come through the package manager. The app is free; if it is useful to you, you can support the development
at [ko-fi.com/samcejko](https://ko-fi.com/samcejko).

By hand: the IPA installs with `ipainstaller -f TikTak-<version>.ipa` (AppSync Unified), or the DEB with `dpkg -i` then
`su mobile -c uicache`. Either works. Do not keep both installed at once.

On iOS 14–17 (64-bit): with a rootless jailbreak add the same repository in Sileo or Zebra, or install the
`iphoneos-arm64` `.deb` with `dpkg -i` (it goes into `/var/jb/Applications`); without a jailbreak open
`TikTak-<version>-arm64.ipa` in [TrollStore](https://github.com/opa334/TrollStore). The same app, the same iOS 6 look;
not tried on a device yet. CI builds both from one source tree (`make package THEOS_PACKAGE_SCHEME=rootless` for arm64,
the iOS 16.5 SDK, deployment target 14.0); the differences live in `src/Util/TKModern.m` and `tools/modern_bundle.py`.

## Project layout

```
pi/           the helper that runs on your server (Python + yt-dlp, Docker)
src/TikTok    the data layer: models, the client that talks to the helper, the "For You" feed and the taste it learns
src/Net       TLS socket, HTTP client, image loader, the media proxy that feeds AVPlayer, the live FLV->HLS repacker
src/UI        the vertical feed and player, profiles, live, saved, comments, what it learned, settings
src/Util      formatting, settings, device helpers
tools         push/build/release/device scripts, icon, asset generator
vendor        mbedTLS configuration and glue (the library is fetched by CI)
```

## Privacy

Your saved videos and what the feed learned live on the device (the gear menu shows it and can forget it). The
app talks only to your own helper and to TikTok's public CDN. No account, no telemetry.

## License

MIT, see `LICENSE`. Third-party notices in `THIRD-PARTY-NOTICES.md`.
