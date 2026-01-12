#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${NEURA_PROJECT_DIR:-"$(cd "$(dirname "$0")/../../Neura_Companion" && pwd)"}"

echo "Neura Companion — macOS one-click build"
echo "ProjectDir: $PROJECT_DIR"

command -v flutter >/dev/null 2>&1 || { echo "flutter not found on PATH"; exit 1; }

pushd "$PROJECT_DIR" >/dev/null
flutter clean
flutter pub get
flutter analyze

echo "Building macOS release app..."
flutter build macos --release

APP_PATH=$(find build/macos/Build/Products/Release -maxdepth 1 -name "*.app" | head -n 1 || true)
if [ -z "$APP_PATH" ]; then
  echo "Could not locate .app bundle."
  exit 1
fi

echo "Built app: $PROJECT_DIR/$APP_PATH"
echo "Tip: To package DMG, use create-dmg or manually zip the .app."
popd >/dev/null
