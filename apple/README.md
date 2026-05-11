# Pano Scrobbler

This directory contains the native Apple codebase for Pano Scrobbler.

The structure is SwiftPM-first so macOS and future iOS targets can share the same
domain model, service clients, metadata pipeline, import/export DTOs, and tests.

- `Apps/macOS`: native macOS SwiftUI app.
- `Packages/Core`: portable models, protocols, metadata transforms, and scrobble engine.
- `Packages/Services`: scrobbling service clients.
- `Packages/Persistence`: SQLite, JSON settings, and Keychain storage.
- `Packages/MacIntegration`: macOS-only now-playing, notification, status item, and launch-at-login integrations.

The direct-distributed macOS build is ad-hoc signed by default and is not
notarized until this fork has an Apple Developer account. A general public API
for reading every other app's Now Playing metadata does not exist on macOS, so
unsupported global media capture remains isolated behind
`GlobalNowPlayingProvider`.

## Build

Use Xcode or Swift 6.2+ on macOS 15 or later.

```bash
swift test --package-path apple
cd apple
mise run build:dev
mise run run:dev
mise run dmg:arm64
mise run dmg:x64
```

Release packaging creates two DMGs:

- `dist/pano-scrobbler-macos-arm64.dmg` for Apple Silicon.
- `dist/pano-scrobbler-macos-x64.dmg` for Intel Macs.

`mise run dmg:universal` remains available for local universal-binary checks,
but the published release artifacts are the split architecture DMGs.

Local builds are ad-hoc signed so strict bundle validation works without a
certificate. Unnotarized release builds may require users to approve the app in
System Settings → Privacy & Security after the first launch attempt.

## Dev and prod variants

Use `mise run run:dev` for development. It builds `Pano Scrobbler Dev.app` with
bundle ID `com.arn.scrobble.mac.dev`, app data directory `Pano Scrobbler Dev`,
and Keychain service `com.arn.scrobble.mac.dev.credentials`.

Use `mise run run:prod` or the release DMG tasks for the production identity:
`Pano Scrobbler.app`, bundle ID `com.arn.scrobble.mac`, app data directory
`Pano Scrobbler`, and Keychain service `com.arn.scrobble.mac.credentials`.

These variants can run side by side and will receive separate Automation
permission prompts.

For production distribution, configure:

- `PANO_DISCORD_CLIENT_ID` to enable Discord Rich Presence in the built app. For
  local builds, pass it in the shell before the `mise` or script command. For
  GitHub releases, store it as an Actions secret named `PANO_DISCORD_CLIENT_ID`.
  Do not put this value in `.env`.
- `MACOS_CODESIGN_IDENTITY`: optional Developer ID Application signing identity.
- `MACOS_DMG_CODESIGN_IDENTITY`: optional DMG signing identity; defaults to the
  app identity.
- `NOTARIZE=1` plus `NOTARYTOOL_PROFILE`, or `APPLE_ID`,
  `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`, when notarization is added
  later.
