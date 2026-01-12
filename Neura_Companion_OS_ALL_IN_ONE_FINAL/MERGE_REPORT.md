# Neura Companion — Avatar Stack Merge Report

This build merges these patch lines into the main codebase:

- Avatar Support (Rive-ready wiring + safe fallbacks)
- Avatar Orchestrator (event-bus-driven state machine)
- Real Sources Bus (hooks for STT/TTS/"thinking" + mood)
- Viseme Sync (optional mouth/viseme numeric channels)
- Dimensional Sync + Error Vault (crash/exception capture + vault logging)

## What you now have

### ✅ Global avatar host (every screen)
- `lib/avatar/avatar_host.dart`
- Wired via `MaterialApp.builder` in `lib/src/app.dart`.

### ✅ Event bus + orchestrator
- `lib/core/neura_event_bus.dart`
- `lib/core/neura_events.dart`
- `lib/avatar/avatar_orchestrator.dart`

### ✅ “Real sources” wiring hooks
- `lib/integrations/neura_sources_hooks.dart`
- `lib/integrations/stt/neura_speech_to_text_bridge.dart` (optional)
- `lib/integrations/tts/neura_flutter_tts_bridge.dart` (optional)

### ✅ Viseme / mouth numeric inputs (optional)
- `lib/core/neura_events_extra.dart`
- `lib/avatar/avatar_controller_viseme_ext.dart`
- `lib/avatar/renderers/rive_avatar_view.dart` now reads numeric inputs:
  - `mouthOpen` (0..1)
  - `viseme` (0..N)

### ✅ Dimensional Sync error capture + vault
- `lib/core/neura_fault_system.dart`
- `lib/core/neura_error_vault.dart`
- `lib/core/src/neura_error_vault_io.dart`
- Hooks wired in `lib/main.dart`.

## Where to drop your animation files
- Rive: `assets/rive/neura_default.riv` (and/or `neuro_default.riv`)
- Lottie: `assets/lottie/neura_default.json` (and/or `neuro_default.json`)

Missing assets are handled safely: Neura falls back to Lottie, then to a sprite placeholder.

## Quick sanity checks
- Launch app → Home screen shows module tiles
- Tap “Test Error Vault” → should not crash; it should emit an error event and log to the vault
- Toggle “Fake Listening/Talking/Thinking” tiles → Neura should react (or fallback view should show status text)

