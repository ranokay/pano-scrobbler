# Pano Scrobbler

This directory contains the native Apple codebase for Pano Scrobbler.

The structure is SwiftPM-first so macOS and future iOS targets can share the same
domain model, service clients, metadata pipeline, import/export DTOs, and tests.

- `Apps/macOS`: native macOS SwiftUI app.
- `Packages/Core`: portable models, protocols, metadata transforms, and scrobble engine.
- `Packages/Services`: scrobbling service clients.
- `Packages/Persistence`: SQLite, JSON settings, and Keychain storage.
- `Packages/MacIntegration`: macOS-only now-playing, notification, status item, and launch-at-login integrations.

The direct-distributed macOS build uses Developer ID signing, hardened runtime,
and notarization for production releases. A general public API for reading every
other app's Now Playing metadata does not exist on macOS, so unsupported global
media capture remains isolated behind `GlobalNowPlayingProvider`.

## Build

Use Xcode or Swift 6.2+ on macOS 15 or later.

```bash
swift test --package-path apple
bash apple/scripts/build_dmg.sh
```

The packaging script creates `dist/pano-scrobbler-macos-universal.dmg` with a
universal app binary. Local builds are ad-hoc signed so strict bundle validation
works without a certificate.

For production distribution, configure:

- `MACOS_CODESIGN_IDENTITY`: Developer ID Application signing identity.
- `MACOS_DMG_CODESIGN_IDENTITY`: optional DMG signing identity; defaults to the app identity.
- `NOTARYTOOL_PROFILE`, or `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`.
- `REQUIRE_NOTARIZATION=1` to fail the build if signing or notarization is not configured.
- `PANO_DISCORD_CLIENT_ID` to enable Discord Rich Presence in the built app.
