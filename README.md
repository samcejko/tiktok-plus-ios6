# TikTak+

An unofficial TikTok viewer for classic iOS, with an iOS 6 interface in Czech and English. The current direct-device implementation is under hardware verification; it no longer needs a Raspberry Pi/helper server.

Public Explore, creator profiles/posts, video and photo links, comments/replies, local saved posts, topic/language preferences and an on-device recommendation model share the native player and bundled TLS stack. TikTok can restrict undocumented endpoints; restricted search/account content is reported explicitly.

The local library includes the last 200 actually watched posts and searchable saved/history lists (author, caption, hashtag or sound, ignoring case and accents). History can be disabled, cleared or edited one post at a time. Hold a video for 0.5×/1×/1.5×/2× playback when the device/media supports it. The feed picker provides direct access to Explore, For You and Following and marks the current selection; account feeds can still be refused by TikTok.

Saved posts can be organized into named collections and a Watch later queue. Favorite creators and sounds have searchable local lists; profile pages also offer a favorite button. Feed filters can hide creators, words/phrases, photo posts and videos longer than a chosen limit. These are device preferences, independent of TikTok follows/blocks. Video menus include ±10-second seeking, restart, clean view, caption copying and post details. Default playback speed and a 15/30/60/90-minute sleep timer are available; comments can be opened in full or copied. Long menus scroll and keep the classic glossy appearance.

Session import is optional. Export cookies for a signed-in tiktok.com browser session to `ttsession.json`, copy it into the app’s Documents folder using File Sharing/Filza, and import it in Settings. The account is verified directly with TikTok and stored in the device Keychain. Never send session exports to an issue tracker or chat. The app deletes the import file only after successful secure storage. Likes, follows, commenting and notifications are not finished/advertised capabilities.

Česky: Aplikace se připojuje přímo k TikToku, pomocný server nepotřebuje. Má klasický vzhled iOS 6 a české i anglické texty. Přihlášení je volitelné; cookies se ověřují u TikToku a ukládají do zabezpečeného úložiště zařízení. Omezená funkce se nesmí tvářit jako hotová nebo zobrazovat cizí účet.

## Build

Theos with the iOS 9.3 SDK: `make package` builds the iOS 6–10 armv7 package. `make package THEOS_PACKAGE_SCHEME=rootless` uses the iOS 16.5 SDK for the modern arm64 build (iOS 14+ IPA, rootless iOS 15+ package). GitHub Actions fetches mbedTLS/CA certificates, generates rounded icon sizes and launch assets, checks source compatibility and builds both packages plus native parser fixture runners.

See [the direct client design and limitations](docs/direct-client.md), [native fixture tests](tests/direct_parser_tests.m), and [third-party attribution](docs/third-party.md). `docs/login-plan.md` is a historical proposal, not the current design.
