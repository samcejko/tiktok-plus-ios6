# Additional third-party attribution

`src/TikTok/TKWebSignature.m` ports the web request checksum already present in `pi/tikie_server.py`. The original algorithm follows Johnserf-Seed/f2 (Apache License 2.0): https://github.com/Johnserf-Seed/f2 . The port is deterministic and has explicit test vectors; it is not a browser or CAPTCHA implementation.

The Apache License text is included in `Resources/licenses-source/Apache-2.0.txt`. Existing mbedTLS, fonts, artwork and other licensing notices remain in their original files/build resources.
