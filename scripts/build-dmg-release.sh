#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_NAME="ClipboardManager"
SCHEME_NAME="ClipboardManager"
PROJECT_PATH="$REPO_ROOT/${PROJECT_NAME}.xcodeproj"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/${PROJECT_NAME}-DMG-Release}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/build/Release}"
RUN_TESTS="${RUN_TESTS:-0}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DMG_FORMAT="${DMG_FORMAT:-UDZO}"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/${PROJECT_NAME}.app"

for command_name in xcodegen xcodebuild codesign ditto hdiutil shasum security; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: required command is not available: $command_name" >&2
    exit 1
  fi
done

detect_signing_identity() {
  local identity_lines
  identity_lines="$(security find-identity -v -p codesigning \
    | sed -nE 's/^[[:space:]]*[0-9]+\)[[:space:]]+[A-Fa-f0-9]+[[:space:]]+"(Developer ID Application: .*)"$/\1/p')"

  local identity_count
  identity_count="$(printf '%s\n' "$identity_lines" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [[ "$identity_count" != "1" ]]; then
    echo "error: set SIGNING_IDENTITY to exactly one Developer ID Application identity" >&2
    printf '%s\n' "$identity_lines" >&2
    exit 1
  fi

  SIGNING_IDENTITY="$(printf '%s\n' "$identity_lines" | sed -n '1p')"
}

if [[ -z "$SIGNING_IDENTITY" ]]; then
  detect_signing_identity
fi

if [[ -z "$DEVELOPMENT_TEAM" ]]; then
  if [[ "$SIGNING_IDENTITY" =~ \(([A-Z0-9]{10})\)$ ]]; then
    DEVELOPMENT_TEAM="${match[1]}"
  else
    echo "error: set DEVELOPMENT_TEAM to the 10-character Apple Team ID" >&2
    exit 1
  fi
fi

if [[ "$SIGNING_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "error: SIGNING_IDENTITY must be a Developer ID Application identity" >&2
  exit 1
fi

cd "$REPO_ROOT"

echo "==> Signing identity: $SIGNING_IDENTITY"
echo "==> Development team: $DEVELOPMENT_TEAM"

echo "==> Generating Xcode project"
xcodegen generate

if [[ "$RUN_TESTS" == "1" ]]; then
  echo "==> Running tests"
  xcodebuild \
    test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO
fi

echo "==> Building and signing Release app"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  PROVISIONING_PROFILE_SPECIFIER= \
  OTHER_CODE_SIGN_FLAGS=--timestamp \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ENABLE_HARDENED_RUNTIME=YES \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Applying Developer ID signature with secure timestamp"
codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --entitlements "$REPO_ROOT/ClipboardManager/Resources/ClipboardManager.entitlements" \
  --sign "$SIGNING_IDENTITY" \
  "$APP_PATH"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ARTIFACT_NAME="${PROJECT_NAME}-macOS-${VERSION}"
DMG_PATH="$OUTPUT_DIR/${ARTIFACT_NAME}.dmg"
CHECKSUM_PATH="${DMG_PATH}.sha256"
DMG_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/${PROJECT_NAME}-dmg.XXXXXX")"

cleanup() {
  rm -rf "$DMG_ROOT"
}
trap cleanup EXIT

echo "==> Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNATURE_DETAILS="$(codesign -dvvv "$APP_PATH" 2>&1)"
if ! print -r -- "$SIGNATURE_DETAILS" | grep '^Timestamp=' >/dev/null; then
  echo "error: app signature does not contain a secure timestamp" >&2
  echo "       ensure the Developer ID certificate is available and signing uses --timestamp" >&2
  exit 1
fi

echo "==> Preparing DMG contents"
mkdir -p "$OUTPUT_DIR"
rm -f "$DMG_PATH" "$CHECKSUM_PATH"
ditto "$APP_PATH" "$DMG_ROOT/${PROJECT_NAME}.app"
ln -s /Applications "$DMG_ROOT/Applications"

echo "==> Creating DMG"
hdiutil create \
  -volname "$PROJECT_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format "$DMG_FORMAT" \
  "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  if ! command -v xcrun >/dev/null 2>&1; then
    echo "error: xcrun is required when NOTARY_PROFILE is set" >&2
    exit 1
  fi

  echo "==> Submitting DMG for notarization"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  echo "warning: DMG is signed through its Developer ID-signed app but not notarized" >&2
  echo "         set NOTARY_PROFILE for external distribution" >&2
fi

(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo "==> Release artifacts"
echo "DMG:      $DMG_PATH"
echo "SHA-256:  $CHECKSUM_PATH"
