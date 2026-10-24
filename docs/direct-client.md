# TikTak+ direct-device implementation (2026-10-24)

This supersedes the old helper-only proposal. The default app connects to TikTok over its bundled TLS stack. There is no required Raspberry Pi, yt-dlp service, public relay, API key, or developer account configuration.

## Data and playback

- Explore, public profiles and creator pagination, video/photo links, comments and replies, suggestions, hashtag/music APIs and live room metadata are fetched on the device.
- `TKDirectParser` normalizes actual TikTok responses. Empty/challenge responses, conflicting status fields, unavailable formats and failed private APIs are errors, not success or invented content.
- Each operation owns a cookie snapshot. Startup bootstrap is shared to avoid concurrent anonymous sessions changing one another’s media credentials.
- Only explicit H.264 renditions are selected. HEVC-only content is not presented as playable on the legacy build. JPEG alternatives are preferred for photos and covers.
- AVPlayer uses the existing loopback media proxy for modern TLS and FLV-to-HLS remuxing. That proxy runs inside the app; it is not a server helper.
- Saved posts, search history, topic/language preferences and the Explore recommender stay local. Saved posts are resolved again before playback; expiring video URLs are not treated as permanent downloads.
- Viewing history keeps at most 200 unique posts, newest first, after two seconds of actual visible playback. Prefetching and seeking alone do not create a history entry. Only metadata is stored; playback URLs and unknown/session fields are excluded. History can be disabled, cleared or individually removed independently of saved posts and feed deduplication. Saved/history filtering ignores case and diacritics.
- Video playback speed can be selected from 0.5×, 1×, 1.5× and 2×. Unsupported device/media speeds are rejected with a message; photo slideshows retain their timing. Seek, loop and pause/resume retain the current video's selected speed.
- Feed and playback menus retain native iOS 6 sheets on iOS 6, with an app-drawn glossy action sheet on newer systems. The latter uses an overlay rather than a system modal, so selecting a speed cannot inadvertently cover/pause the feed or lose the next menu during dismissal.
- Explore remains a distinct, always-accessible feed after sign-in. For You and Following never silently substitute Explore.

## Account identity and secrets

- Imports accept Cookie-Editor arrays/wrappers, JSON cookie maps, Netscape exports and Cookie headers. Non-TikTok domains, expired session cookies, header injection and ambiguous duplicates are rejected.
- Cookie presence is not proof of login. Only a successful authenticated passport account-info response containing both a user ID and handle can establish identity. Tracking cookies are treated as opaque values. A public profile can enrich the account only when its ID exactly matches the authenticated ID; public hydration alone never establishes identity.
- A successful import is staged until `TKSession` confirms it is still the latest request. Sign-out or a newer import invalidates late callbacks.
- The session is committed atomically to Keychain with `AfterFirstUnlockThisDeviceOnly`. Account cookies have no plaintext preferences fallback. The imported file is removed only after secure persistence succeeds.
- Legacy helper tokens are not accepted as proof of a local TikTok session. Existing helper session files/services are not remotely modified by the app.
- Imported account cookies go only to the matching TikTok domain and path over verified HTTPS. Media CDNs receive only their anonymous chain token. Cross-host redirects strip cookies and account headers, and HTTPS downgrades are rejected.
- A private feed is preceded by a fresh authenticated identity check. Temporary network/schema/challenge failures do not erase credentials; confirmed expiry invalidates login through the session controller.

## Explicit limits

TikTok’s undocumented web endpoints can refuse requests or require a supported browser. Keyword search, hashtag/music pages, account feeds and live availability must be tested separately; working Explore does not prove those features work. The app reports refusal as an error, rather than “nothing found.” General browser login/QR login, sending likes/follows/comments and notifications are not advertised as finished features. No account actions are sent automatically.

The legacy target remains iOS 6–10 (armv7); the separate modern target is iOS 14+ (arm64 IPA), with a rootless package for iOS 15+. The existing UICollectionView-based interface is not an iOS 5 implementation.

## Verification

`tests/direct_parser_tests.m` exercises real parsing logic: authentication proof, cookie import formats and rejection cases, exact 64-bit IDs, status validation, H.264 selection, photo posts, profile/comment normalization and deterministic web checksum vectors. CI builds the runner for both architectures. The same checks can run inside the actual app with the locally gated diagnostic command.

Diagnostics require a `Documents/debug` file. `tiktakplus:selftest` runs the parser fixtures and a temporary Keychain write/read/delete check, then writes only pass/failure information; `tiktakplus:feedback` writes counts/player state. Neither exports cookies or account identity. Remove `Documents/debug` after hardware verification.

Hardware results and any remaining limitations are recorded in the local audit report before a public release is considered ready.
