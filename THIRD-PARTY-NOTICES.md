# Third-party notices

TikTak (first called Tikie) is an independent, unofficial viewer of public TikTok content. It is not affiliated with, endorsed by or
associated with TikTok or ByteDance. TikTok is a trademark of ByteDance. The app reads public videos through a
helper you run on your own server; using an unofficial client may be against TikTok's terms of service, which is
the user's call. No login, no posting, no access to private content.

## On the device (the app)

- **Mbed TLS** - Apache License 2.0. The TLS 1.2 client for every HTTPS request (iOS 6's own stack cannot talk to
  modern servers). https://github.com/Mbed-TLS/mbedtls
- **Mozilla CA certificate bundle** (curl.se/ca) - MPL-2.0. The roots TLS connections are checked against.
- **Theos** - the build system; not shipped in the app.

## On your server (the helper)

- **yt-dlp** - Unlicense / public domain. Fetches the public video lists and direct URLs. https://github.com/yt-dlp/yt-dlp
- **f2** (Johnserf-Seed) - Apache License 2.0. The helper's X-Bogus signature (`x_bogus` in `pi/tikie_server.py`,
  used for search, hashtags and sounds) follows its `xbogus.py`. https://github.com/Johnserf-Seed/f2
- **Python** - PSF License.

The license texts of the shipped libraries are included in the app bundle (Settings).

## Protocol references

The independently implemented TikTok web account-action paths and parameter names were cross-checked against caixax/opentok's MIT-licensed endpoints.ts and signedFetch.ts (2026-10-24): https://github.com/caixax/opentok/tree/main/src/main/tiktok . Its Electron/browser signer is not bundled or used. The on-device signature implementation has different capabilities; live acceptance of writes must be validated separately.

- **SuperDuperNoob/tiktok-xgnarly-decoded** — MIT, copyright 2026. The native TKGnarlySignature implementation adapts its independently reconstructed signing wire format and cipher. Upstream: https://github.com/SuperDuperNoob/tiktok-xgnarly-decoded . Full license: docs/licenses/tiktok-xgnarly-LICENSE.txt, also bundled in Resources/licenses. Deterministic native output is compared against the upstream encoder with pinned time/entropy.
