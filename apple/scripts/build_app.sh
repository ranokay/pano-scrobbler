#!/usr/bin/env bash
set -euo pipefail

BUILD_PRODUCT_NAME="PanoScrobbler"
MIN_SYSTEM_VERSION="15.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
APPLE_DIR="$ROOT_DIR/apple"
DIST_DIR="$ROOT_DIR/dist"
ICON_FILE="$APPLE_DIR/Apps/macOS/Resources/AppIcon.icns"
# Optional: macOS 26 Liquid Glass icon bundle exported from Icon Composer.
# Ships alongside .icns so older macOS versions still get a valid fallback.
ICON_BUNDLE="$APPLE_DIR/Apps/macOS/Resources/AppIcon.icon"
ENTITLEMENTS_FILE="$APPLE_DIR/Apps/macOS/PanoScrobbler.entitlements"
CONFIGURATION="${CONFIGURATION:-release}"
ARCHS="${ARCHS:-arm64 x86_64}"
CODESIGN_IDENTITY="${MACOS_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}"

APP_VARIANT="${APP_VARIANT:-prod}"
case "$APP_VARIANT" in
  prod|production)
    APP_VARIANT="prod"
    DEFAULT_APP_DISPLAY_NAME="Pano Scrobbler"
    DEFAULT_APP_EXECUTABLE="PanoScrobbler"
    DEFAULT_BUNDLE_ID="com.arn.scrobble.mac"
    DEFAULT_APP_DATA_DIRECTORY_NAME="Pano Scrobbler"
    DEFAULT_KEYCHAIN_SERVICE="com.arn.scrobble.mac.credentials"
    DEFAULT_WINDOW_AUTOSAVE_NAME="PanoScrobblerMainWindow"
    ;;
  dev|development)
    APP_VARIANT="dev"
    DEFAULT_APP_DISPLAY_NAME="Pano Scrobbler Dev"
    DEFAULT_APP_EXECUTABLE="PanoScrobblerDev"
    DEFAULT_BUNDLE_ID="com.arn.scrobble.mac.dev"
    DEFAULT_APP_DATA_DIRECTORY_NAME="Pano Scrobbler Dev"
    DEFAULT_KEYCHAIN_SERVICE="com.arn.scrobble.mac.dev.credentials"
    DEFAULT_WINDOW_AUTOSAVE_NAME="PanoScrobblerDevMainWindow"
    ;;
  *)
    echo "APP_VARIANT must be 'prod' or 'dev'." >&2
    exit 1
    ;;
esac

APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-$DEFAULT_APP_DISPLAY_NAME}"
APP_EXECUTABLE="${APP_EXECUTABLE:-$DEFAULT_APP_EXECUTABLE}"
BUNDLE_ID="${BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
APP_DATA_DIRECTORY_NAME="${APP_DATA_DIRECTORY_NAME:-$DEFAULT_APP_DATA_DIRECTORY_NAME}"
KEYCHAIN_SERVICE="${KEYCHAIN_SERVICE:-$DEFAULT_KEYCHAIN_SERVICE}"
WINDOW_AUTOSAVE_NAME="${WINDOW_AUTOSAVE_NAME:-$DEFAULT_WINDOW_AUTOSAVE_NAME}"
APP_BUNDLE="${APP_BUNDLE:-$DIST_DIR/$APP_DISPLAY_NAME.app}"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
INFO_PLIST="$APP_CONTENTS/Info.plist"

VERSION_CODE="${VERSION_CODE:-$(tr -cd '0-9' < "$ROOT_DIR/version.txt")}"
if [[ -z "$VERSION_CODE" ]]; then
  VERSION_CODE="${GITHUB_RUN_NUMBER:-0}"
fi
VERSION_NAME="${VERSION_NAME:-$((10#$VERSION_CODE / 100)).$((10#$VERSION_CODE % 100))}"

if [[ ! -f "$ICON_FILE" ]]; then
  echo "Missing app icon: $ICON_FILE" >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS_FILE" ]]; then
  echo "Missing entitlements: $ENTITLEMENTS_FILE" >&2
  exit 1
fi

read -r -a ARCH_ARRAY <<< "$ARCHS"
if [[ "${#ARCH_ARRAY[@]}" -eq 0 ]]; then
  echo "ARCHS must contain at least one architecture." >&2
  exit 1
fi

binaries=()
for arch in "${ARCH_ARRAY[@]}"; do
  swift build --package-path "$APPLE_DIR" --configuration "$CONFIGURATION" --arch "$arch"
  build_dir="$(swift build --package-path "$APPLE_DIR" --configuration "$CONFIGURATION" --arch "$arch" --show-bin-path)"
  binary="$build_dir/$BUILD_PRODUCT_NAME"

  if [[ ! -x "$binary" ]]; then
    echo "Missing built executable for $arch: $binary" >&2
    exit 1
  fi

  binaries+=("$binary")
done

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

if [[ "${#binaries[@]}" -eq 1 ]]; then
  cp "${binaries[0]}" "$APP_MACOS/$APP_EXECUTABLE"
else
  lipo -create "${binaries[@]}" -output "$APP_MACOS/$APP_EXECUTABLE"
fi
chmod +x "$APP_MACOS/$APP_EXECUTABLE"

cp "$ICON_FILE" "$APP_RESOURCES/AppIcon.icns"

# Copy the macOS 26 Liquid Glass icon bundle if it exists. This makes the
# icon render full-bleed in the new icon system; without it, macOS 26 wraps
# legacy .icns icons in a default tile with gray padding.
if [[ -d "$ICON_BUNDLE" ]]; then
  cp -R "$ICON_BUNDLE" "$APP_RESOURCES/AppIcon.icon"
fi

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
  <key>CFBundleIconName</key>
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
  <string>Pano Scrobbler uses Automation permission to read now-playing metadata from Music and Spotify.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSUserNotificationsUsageDescription</key>
  <string>Pano Scrobbler shows now-playing and scrobble status notifications.</string>
  <key>PanoAppDataDirectoryName</key>
  <string>$APP_DATA_DIRECTORY_NAME</string>
  <key>PanoBuildVariant</key>
  <string>$APP_VARIANT</string>
  <key>PanoKeychainService</key>
  <string>$KEYCHAIN_SERVICE</string>
  <key>PanoWindowAutosaveName</key>
  <string>$WINDOW_AUTOSAVE_NAME</string>
</dict>
</plist>
PLIST

if [[ -n "${PANO_DISCORD_CLIENT_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :DiscordClientID string ${PANO_DISCORD_CLIENT_ID}" "$INFO_PLIST"
fi

plutil -lint "$INFO_PLIST"

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  codesign --force --deep --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS_FILE" \
    --sign "$CODESIGN_IDENTITY" \
    "$APP_BUNDLE"
else
  echo "MACOS_CODESIGN_IDENTITY is not set; ad-hoc signing $APP_BUNDLE for local validation."
  codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS_FILE" \
    --sign - \
    "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=4 "$APP_BUNDLE"
lipo -info "$APP_MACOS/$APP_EXECUTABLE"

echo "Built $APP_BUNDLE"
