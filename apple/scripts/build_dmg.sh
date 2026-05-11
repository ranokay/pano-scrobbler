#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DMG_SIGN_IDENTITY="${MACOS_DMG_CODESIGN_IDENTITY:-${MACOS_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"
NOTARIZE="${NOTARIZE:-0}"
ARCHS="${ARCHS:-arm64 x86_64}"

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

read -r -a ARCH_ARRAY <<< "$ARCHS"
if [[ "${#ARCH_ARRAY[@]}" -eq 0 ]]; then
  echo "ARCHS must contain at least one architecture." >&2
  exit 1
fi

arch_label() {
  case "$1" in
    arm64) echo "arm64" ;;
    x86_64) echo "x64" ;;
    *) echo "$1" | tr -c '[:alnum:]' '-' ;;
  esac
}

if [[ "${#ARCH_ARRAY[@]}" -gt 1 ]]; then
  ARCH_NAME="universal"
else
  ARCH_NAME="$(arch_label "${ARCH_ARRAY[0]}")"
fi

DMG_NAME="${DMG_NAME:-pano-scrobbler-macos-${ARCH_NAME}.dmg}"
DMG_PATH="$DIST_DIR/$DMG_NAME"

if [[ "${SKIP_APP_BUILD:-0}" != "1" ]]; then
  APP_VARIANT="$APP_VARIANT" \
  APP_DISPLAY_NAME="$APP_DISPLAY_NAME" \
  APP_EXECUTABLE="$APP_EXECUTABLE" \
  BUNDLE_ID="$BUNDLE_ID" \
  APP_DATA_DIRECTORY_NAME="$APP_DATA_DIRECTORY_NAME" \
  KEYCHAIN_SERVICE="$KEYCHAIN_SERVICE" \
  WINDOW_AUTOSAVE_NAME="$WINDOW_AUTOSAVE_NAME" \
  APP_BUNDLE="$APP_BUNDLE" \
  ARCHS="$ARCHS" \
  "${SCRIPT_DIR}/build_app.sh"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing app bundle: $APP_BUNDLE" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pano-scrobbler-dmg.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

DMG_ROOT="$WORK_DIR/dmg-root"
mkdir -p "$DMG_ROOT" "$DIST_DIR"
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
lipo -info "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"

if [[ -n "$DMG_SIGN_IDENTITY" ]]; then
  codesign --force --timestamp --sign "$DMG_SIGN_IDENTITY" "$DMG_PATH"
  codesign -dvvv "$DMG_PATH"
else
  echo "No Developer ID identity configured for DMG signing."
fi

if [[ "$REQUIRE_NOTARIZATION" == "1" ]]; then
  NOTARIZE=1
fi

can_notarize=0
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  can_notarize=1
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  can_notarize=1
fi

if [[ "$NOTARIZE" == "1" && -z "$DMG_SIGN_IDENTITY" ]]; then
  echo "NOTARIZE=1 but no Developer ID signing identity was configured." >&2
  exit 1
fi

if [[ "$NOTARIZE" == "1" && "$can_notarize" != "1" ]]; then
  echo "NOTARIZE=1 but no notarytool credentials were configured." >&2
  exit 1
fi

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  else
    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait
  fi

  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  echo "Skipping notarization. Set NOTARIZE=1 and configure Developer ID credentials to notarize."
fi

if [[ -n "$DMG_SIGN_IDENTITY" && "$NOTARIZE" == "1" ]]; then
  spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
fi

echo "Created $DMG_PATH"
