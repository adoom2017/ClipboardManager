#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_NAME="ClipboardManager"
SCHEME_NAME="ClipboardManager"
PROJECT_PATH="$REPO_ROOT/${PROJECT_NAME}.xcodeproj"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/${PROJECT_NAME}-Release}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/build/Release}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/${PROJECT_NAME}.app"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is not installed" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is not available" >&2
  exit 1
fi

echo "==> Generating Xcode project"
cd "$REPO_ROOT"
xcodegen generate

echo "==> Building Release app"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Preparing output directory"
mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/${PROJECT_NAME}.app"
cp -R "$APP_PATH" "$OUTPUT_DIR/"

echo "Release app ready:"
echo "  $OUTPUT_DIR/${PROJECT_NAME}.app"
