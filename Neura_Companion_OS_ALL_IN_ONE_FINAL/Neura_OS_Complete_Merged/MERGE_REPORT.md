# Neura Merge Report

Merged modules into `Neura_OS_Complete_Merged/neura_os`

## Included Packs
- Merged Unity World Core: world/NeuraWorld -> Neura_OS_Complete_Merged/world/NeuraWorld
- Merged Unity Flutter Bridge: flutter/lib -> neura_os/lib
- Copied README_EmotionLighting_Flutter.md -> docs/
- Merged Emotion Lighting System: flutter/lib -> neura_os/lib, unity/Assets -> Neura_OS_Complete_Merged/unity/Assets
- Copied Intent Engine README -> docs/
- Merged Intent Engine: lib/core/intent -> neura_os/lib/core/intent
- Copied Memory Graph README -> docs/
- Merged Memory Graph (crypto + service) into neura_os/lib/core/memory (drift db skipped to avoid codegen).
- Copied ContentGen README -> docs/
- Merged Content Engine: lib/core/content -> neura_os/lib/core/content
- Merged Rive Resident widgets + assets/rive README into neura_os.
- Merged RiveRig King assets into neura_os/assets (includes assets/rive + lottie + images).
- Updated lib/main.dart to initialize NeuraVoicePack (crash-safe).
- Updated lib/src/app.dart to wrap NeuraShell with NeuraShellRoot (persistent resident overlay).
- Moved neura_bridge.dart -> neura_bridge_io.dart (contains dart:io usage).
- Created conditional neura_bridge.dart facade + web stub for safe compilation across platforms.
- Updated pubspec.yaml: added deps (lottie, rive, firebase/auth, etc.) and assets (lottie, rive).
- Rewrote MemoryGraphService to file-based encrypted JSONL store (removed drift/codegen dependency).
- Added services/neura_core_services.dart (MemoryGraph + IntentEngine + ContentEngine singletons).

## Notes
- `MemoryGraphService` was rewritten to avoid Drift codegen and keep builds stable.
- `NeuraBridge` was made web-safe via conditional imports (`neura_bridge_stub.dart` / `neura_bridge_io.dart`).
- `pubspec.yaml` was updated to include missing deps referenced in code and to register `assets/lottie/` and `assets/rive/`.
