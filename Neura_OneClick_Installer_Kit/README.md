# Neura Companion — One-Click Installer Kit

This kit provides one-click build/install scripts for:
- Windows (build + run / optional installer packaging)
- Android (APK release build)
- macOS (app build; optional DMG packaging)

Prereqs (same across platforms):
- Flutter SDK installed and on PATH
- Git installed (optional but recommended)
- Platform build deps:
  - Windows: Visual Studio Build Tools + Desktop development with C++
  - Android: Android SDK + platform tools configured for Flutter
  - macOS: Xcode installed

## Quick Start
1) Put your project folder next to this kit OR set NEURA_PROJECT_DIR.
2) Run the appropriate script for your platform.

Project input:
- Default: ../Neura_Companion (relative to this kit)
- Override: set environment variable NEURA_PROJECT_DIR to your Flutter project path
