# Pano Scrobbler

This directory contains the native Apple codebase for Pano Scrobbler.

The structure is SwiftPM-first so macOS and future iOS targets can share the same
domain model, service clients, metadata pipeline, import/export DTOs, and tests.

- `Apps/macOS`: native macOS SwiftUI app.
- `Packages/Core`: portable models, protocols, metadata transforms, and scrobble engine.
- `Packages/Services`: scrobbling service clients.
- `Packages/Persistence`: SQLite, JSON settings, and Keychain storage.
- `Packages/MacIntegration`: macOS-only now-playing, notification, status item, and launch-at-login integrations.

The direct-notarized macOS build can use broader integrations than a Mac App
Store build. A general public API for reading every other app's Now Playing
metadata does not exist on macOS, so unsupported global media capture remains
isolated behind `GlobalNowPlayingProvider`.

## Build

Use Xcode 26 or Swift 6.2+ on macOS 26 or later.

```bash
swift test --package-path apple
bash apple/scripts/build_dmg.sh
```

The packaging script creates `dist/pano-scrobbler-macos-arm64.dmg` on Apple
Silicon hosts. The DMG is not notarized yet, so first launch requires using
right-click > Open in Finder.
