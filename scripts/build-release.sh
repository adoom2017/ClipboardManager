#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_NAME="ClipboardManager"
SCHEME_NAME="ClipboardManager"
PROJECT_PATH="$REPO_ROOT/${PROJECT_NAME}.xcodeproj"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/${PROJECT_NAME}-Release}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/build/Release}"
RUN_TESTS="${RUN_TESTS:-0}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/${PROJECT_NAME}.app"

for command_name in xcodegen xcodebuild codesign ditto shasum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: required command is not available: $command_name" >&2
    exit 1
  fi
done

cd "$REPO_ROOT"

echo "==> Generating Xcode project"
xcodegen generate

if [[ "$RUN_TESTS" == "1" ]]; then
  echo "==> Running tests"
  xcodebuild \
    test \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH"
fi

echo "==> Building Release app"
build_args=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME_NAME"
  -configuration Release
  -destination 'platform=macOS'
  -derivedDataPath "$DERIVED_DATA_PATH"
  CODE_SIGNING_ALLOWED=YES
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
  ENABLE_HARDENED_RUNTIME=YES
  build
)

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  # Ad-hoc signing does not use a Keychain private key and must not prompt
  # for a login password, even if DEVELOPMENT_TEAM is exported globally.
  build_args+=(
    CODE_SIGN_STYLE=Manual
    DEVELOPMENT_TEAM=
  )
elif [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  build_args+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
fi

xcodebuild "${build_args[@]}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app not found at $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ARTIFACT_NAME="${PROJECT_NAME}-macOS-${VERSION}"
STAGED_APP="$OUTPUT_DIR/${PROJECT_NAME}.app"
ZIP_PATH="$OUTPUT_DIR/${ARTIFACT_NAME}.zip"
CHECKSUM_PATH="${ZIP_PATH}.sha256"

echo "==> Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Packaging $ARTIFACT_NAME"
mkdir -p "$OUTPUT_DIR"
rm -rf "$STAGED_APP"
rm -f "$ZIP_PATH" "$CHECKSUM_PATH"
ditto "$APP_PATH" "$STAGED_APP"
ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$ZIP_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "error: NOTARY_PROFILE requires a Developer ID SIGNING_IDENTITY" >&2
    exit 1
  fi
  if ! command -v xcrun >/dev/null 2>&1; then
    echo "error: xcrun is required for notarization" >&2
    exit 1
  fi

  echo "==> Submitting archive for notarization"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$STAGED_APP"
  xcrun stapler validate "$STAGED_APP"
  spctl --assess --type execute --verbose=2 "$STAGED_APP"

  rm -f "$ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$ZIP_PATH"
fi

(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo "==> Release artifacts"
echo "App:      $STAGED_APP"
echo "Archive:  $ZIP_PATH"
echo "SHA-256:  $CHECKSUM_PATH"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "note: app is ad-hoc signed; use SIGNING_IDENTITY and DEVELOPMENT_TEAM for external distribution"
elif [[ -z "$NOTARY_PROFILE" ]]; then
  echo "note: app is signed but not notarized; set NOTARY_PROFILE for external distribution"
fi
