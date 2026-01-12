#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${NEURA_PROJECT_DIR:-"$(cd "$(dirname "$0")/../../Neura_Companion" && pwd)"}"

echo "Neura Companion — Android one-click build"
echo "ProjectDir: $PROJECT_DIR"

command -v flutter >/dev/null 2>&1 || { echo "flutter not found on PATH"; exit 1; }

pushd "$PROJECT_DIR" >/dev/null
flutter clean
flutter pub get
flutter analyze

echo "Building Android release APK..."
flutter build apk --release

APK_PATH=$(find build/app/outputs/flutter-apk -maxdepth 1 -name "*release*.apk" | head -n 1 || true)
if [ -z "$APK_PATH" ]; then
  echo "Could not locate release APK."
  exit 1
fi

echo "Built APK: $PROJECT_DIR/$APK_PATH"
popd >/dev/null
