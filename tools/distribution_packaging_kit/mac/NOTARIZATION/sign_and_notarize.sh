#!/usr/bin/env bash
set -euo pipefail

# Set these:
APP_NAME="Neura Companion.app"
PROJECT_DIR="${NEURA_PROJECT_DIR:-"$(cd "$(dirname "$0")/../../Neura_Companion" && pwd)"}"
IDENTITY="${APPLE_SIGN_IDENTITY:-"Developer ID Application: YOUR NAME (TEAMID)"}"
PROFILE="${NOTARY_PROFILE:-"AC_NOTARY"}"

echo "ProjectDir: $PROJECT_DIR"
pushd "$PROJECT_DIR" >/dev/null

flutter clean
flutter pub get
flutter analyze
flutter build macos --release

APP_PATH="build/macos/Build/Products/Release/$APP_NAME"
if [ ! -d "$APP_PATH" ]; then
  echo "App not found at $APP_PATH"
  exit 1
fi

echo "Codesigning (deep) with hardened runtime..."
codesign --deep --force --options runtime --sign "$IDENTITY" "$APP_PATH"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ZIP_OUT="Neura_Companion_macOS.zip"
echo "Creating ZIP: $ZIP_OUT"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_OUT"

echo "Submitting for notarization..."
xcrun notarytool submit "$ZIP_OUT" --keychain-profile "$PROFILE" --wait

echo "Stapling..."
xcrun stapler staple "$APP_PATH"

echo "Assessing with spctl..."
spctl --assess --verbose "$APP_PATH" || true

echo "Done. Output: $PROJECT_DIR/$ZIP_OUT"
popd >/dev/null
