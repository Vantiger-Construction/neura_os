# Neura OS (Merged Build)

This is the **merged** Neura OS Flutter project with the upgrades/patches you uploaded applied into one codebase.

## Included modules
- Legacy Vault
- Neura Spaces (rooms + map)
- Focus Office + Ambient FX
- Mood Check-In + Mood History
- Journal Prompt + Voice Journal
- Dream Visualizer + Dream Calendar + Monthly Dream Show
- Settings + Diagnostics
- **Voice Lab** (offline voice clips + live microphone visemes)

## Neura Engine direction

The [Neura Engine vision and implementation milestones](docs/NEURA_ENGINE_VISION.md)
describe a dedicated engine for ongoing reflection and learning from approved
information, with user control over memory and actions. The
[milestone 1 synthetic IPC slice](docs/NEURA_ENGINE_IPC_M1.md) now includes an
authenticated Rust sidecar and a Windows Console session with explicit
start, pause, resume, and stop controls. It remains a synthetic-only check that
uses the echo adapter by default; an explicit `ollama-local` opt-in can run the
same fixed fixtures on a pinned local model
([milestone 2 slice](docs/NEURA_ENGINE_MODEL_ADAPTER_M2.md)). Milestones 1 and 2
are incomplete, and reflection and personal sources are not enabled.

## Quick start (Windows)
1. Install Flutter (and Android Studio if you want APK builds)
2. From this folder, run:
   - `scripts\\Install-Neura-OS.bat`  (or)
   - `scripts\\Install-Neura-OS.ps1`

## Manual commands
```bash
flutter pub get
flutter run
# Release build:
flutter build apk --release
```

## Voice assets
Voice samples are bundled at:
- `assets/audio/neura/*.wav`

The Voice Lab screen lets you:
- Play a voice clip
- Toggle live microphone mouth/viseme driver (offline)

## Notes
- Android/iOS permission files may need to be added depending on the Flutter template you deploy into.
- If you already have a fuller Android/ios folder in your main repo, drop this `lib/` + `assets/` + `pubspec.yaml` in and run `flutter pub get`.
