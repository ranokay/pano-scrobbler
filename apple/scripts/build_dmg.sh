#!/usr/bin/env bash
set -euo pipefail

APP_DISPLAY_NAME="Pano Scrobbler"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="${APP_BUNDLE:-$DIST_DIR/$APP_DISPLAY_NAME.app}"
DMG_SIGN_IDENTITY="${MACOS_DMG_CODESIGN_IDENTITY:-${MACOS_CODESIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"
ARCHS="${ARCHS:-arm64 x86_64}"

case "$(uname -m)" in
  arm64) HOST_ARCH_NAME="arm64" ;;
  x86_64) HOST_ARCH_NAME="x64" ;;
  *) HOST_ARCH_NAME="$(uname -m)" ;;
esac

if [[ "$ARCHS" == *" "* ]]; then
  ARCH_NAME="universal"
else
  ARCH_NAME="${ARCHS:-$HOST_ARCH_NAME}"
fi

DMG_NAME="${DMG_NAME:-pano-scrobbler-macos-${ARCH_NAME}.dmg}"
DMG_PATH="$DIST_DIR/$DMG_NAME"

if [[ "${SKIP_APP_BUILD:-0}" != "1" ]]; then
  "$SCRIPT_DIR/build_app.sh"
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

if [[ -n "$DMG_SIGN_IDENTITY" ]]; then
  codesign --force --timestamp --sign "$DMG_SIGN_IDENTITY" "$DMG_PATH"
  codesign -dvvv "$DMG_PATH"
else
  echo "No Developer ID identity configured for DMG signing."
fi

can_notarize=0
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  can_notarize=1
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  can_notarize=1
fi

if [[ "$REQUIRE_NOTARIZATION" == "1" && -z "$DMG_SIGN_IDENTITY" ]]; then
  echo "REQUIRE_NOTARIZATION=1 but no Developer ID signing identity was configured." >&2
  exit 1
fi

if [[ "$REQUIRE_NOTARIZATION" == "1" && "$can_notarize" != "1" ]]; then
  echo "REQUIRE_NOTARIZATION=1 but no notarytool credentials were configured." >&2
  exit 1
fi

if [[ "$can_notarize" == "1" && -n "$DMG_SIGN_IDENTITY" ]]; then
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
elif [[ "$can_notarize" == "1" ]]; then
  echo "Skipping notarization because the DMG was not signed."
else
  echo "Skipping notarization because notarytool credentials are not configured."
fi

if [[ -n "$DMG_SIGN_IDENTITY" ]]; then
  spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
fi

echo "Created $DMG_PATH"
