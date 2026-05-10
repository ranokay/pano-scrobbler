#!/usr/bin/env bash
set -euo pipefail

APP_DISPLAY_NAME="Pano Scrobbler"
APP_EXECUTABLE="PanoScrobbler"
BUNDLE_ID="com.arn.scrobble.mac"
MIN_SYSTEM_VERSION="26.0"
RESOURCE_BUNDLE_NAME="PanoScrobbler_PanoScrobbler.bundle"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
APPLE_DIR="$ROOT_DIR/apple"
DIST_DIR="$ROOT_DIR/dist"
ICON_FILE="$APPLE_DIR/Apps/macOS/Resources/AppIcon.icns"

VERSION_CODE="${VERSION_CODE:-$(tr -cd '0-9' < "$ROOT_DIR/version.txt")}"
if [[ -z "$VERSION_CODE" ]]; then
  VERSION_CODE="${GITHUB_RUN_NUMBER:-0}"
fi
VERSION_NAME="${VERSION_NAME:-$((10#$VERSION_CODE / 100)).$((10#$VERSION_CODE % 100))}"

case "$(uname -m)" in
  arm64) ARCH_NAME="arm64" ;;
  x86_64) ARCH_NAME="x64" ;;
  *) ARCH_NAME="$(uname -m)" ;;
esac

DMG_NAME="pano-scrobbler-macos-${ARCH_NAME}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

swift build --package-path "$APPLE_DIR" --configuration release
BUILD_DIR="$(swift build --package-path "$APPLE_DIR" --configuration release --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_EXECUTABLE"
RESOURCE_BUNDLE="$BUILD_DIR/$RESOURCE_BUNDLE_NAME"

if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "Missing built executable: $BUILD_BINARY" >&2
  exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Missing SwiftPM resource bundle: $RESOURCE_BUNDLE" >&2
  exit 1
fi

if [[ ! -f "$ICON_FILE" ]]; then
  echo "Missing app icon: $ICON_FILE" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pano-scrobbler-dmg.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

APP_BUNDLE="$WORK_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
INFO_PLIST="$APP_CONTENTS/Info.plist"
DMG_ROOT="$WORK_DIR/dmg-root"

mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$DMG_ROOT" "$DIST_DIR"
cp "$BUILD_BINARY" "$APP_MACOS/$APP_EXECUTABLE"
chmod +x "$APP_MACOS/$APP_EXECUTABLE"
cp "$ICON_FILE" "$APP_RESOURCES/AppIcon.icns"
cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/$RESOURCE_BUNDLE_NAME"

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION_NAME</string>
  <key>CFBundleVersion</key>
  <string>$VERSION_CODE</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.music</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Pano Scrobbler reads Now Playing metadata from Music and Spotify when you enable those integrations.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSUserNotificationsUsageDescription</key>
  <string>Pano Scrobbler shows now-playing and scrobble status notifications.</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST"

cp -R "$APP_BUNDLE" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_DISPLAY_NAME" \
  -srcfolder "$DMG_ROOT" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

hdiutil verify "$DMG_PATH"
echo "Created $DMG_PATH"
