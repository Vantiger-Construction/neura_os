# Neura Companion — NEXT Patch: Dimensional Sync + Error Vault (Crash‑Safe)

What this adds:
- Global error boundary (FlutterError + PlatformDispatcher + ErrorWidget)
- Emits typed events on your NeuraEventBus
- Drives the AvatarController into an "error / recovery" animation state (safe if inputs missing)
- Writes errors to a local JSONL "vault" (desktop/mobile only; web is a no‑op)
- Zero new pubspec dependencies

## 1) Drop-in files
Merge the `lib/` folder into your project.

## 2) main.dart wiring (minimal)
Add imports:

```dart
import 'core/neura_event_bus.dart';
import 'core/neura_fault_system.dart';
import 'avatar/avatar_globals.dart';
```

Then BEFORE `runApp(...)`:

```dart
NeuraFaultSystem.install(
  bus: NeuraEventBus.I,
  controller: AvatarGlobals.controller,
);
```

That's it. Now:
- Any uncaught Flutter exception triggers Dimensional Sync Recovery
- Your avatar will flip to `isError=true` briefly (if your Rive has it)
- A friendly error UI renders instead of a red screen (still shows details button)

## 3) Optional: customize the voice line / copy
Edit: `lib/core/neura_fault_system.dart` -> `defaultUserFacingMessage`.

## Notes
- Vault file path uses `Directory.systemTemp` so it never breaks builds.
- Web builds: vault is a no‑op (no dart:io).
