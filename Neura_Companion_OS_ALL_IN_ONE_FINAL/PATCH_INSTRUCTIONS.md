# Neura Companion – Avatar Orchestrator Patch

This patch adds an **app-wide signal bus + avatar orchestrator** so Neura can react to:
- navigation (room changes)
- global errors (with safe recovery + optional “Dimensional Sync” flavor)
- tool/network activity (thinking)
- voice lifecycle (listening/talking)
- app lifecycle (foreground/background)

## What you get
- `NeuraEventBus` (typed events; no dependencies)
- `AvatarOrchestrator` (listens to bus and drives `AvatarController`)
- `AvatarRouteObserver` (turns route changes into events)
- `NeuraDiagnostics.wireGlobalErrorHooks()` (captures Flutter + platform errors safely)

## Install
1) Drop these files into your project root (merge folders).
2) Add the snippet below to `main.dart`.

### Minimal wiring snippet (safe)
Add these imports:
```dart
import 'core/neura_diagnostics.dart';
import 'core/neura_event_bus.dart';
import 'avatar/avatar_orchestrator.dart';
import 'avatar/avatar_route_observer.dart';
import 'avatar/avatar_globals.dart';
```

Then, inside `main()` *before* `runApp(...)`:
```dart
NeuraDiagnostics.wireGlobalErrorHooks(
  onErrorEvent: (e) => NeuraEventBus.I.emit(e),
);

// Start orchestrator (drives Neura’s expressions based on events)
final orchestrator = AvatarOrchestrator(
  controller: AvatarGlobals.controller,
  bus: NeuraEventBus.I,
)..start();
```

Finally, in `MaterialApp(...)` add the observer:
```dart
navigatorObservers: [AvatarRouteObserver(NeuraEventBus.I)],
```

### Optional: stop orchestrator on dispose
If you keep a reference, call `orchestrator.dispose()` when appropriate.
Most apps can just keep it alive for the whole process lifetime.

## How to trigger reactions from anywhere
```dart
NeuraEventBus.I.emit(const NeuraThinkingEvent(true));
NeuraEventBus.I.emit(const NeuraThinkingEvent(false));

NeuraEventBus.I.emit(const NeuraListeningEvent(true));
NeuraEventBus.I.emit(const NeuraTalkingEvent(true));

NeuraEventBus.I.emit(NeuraMoodEvent(mood: 0.4, energy: 0.7));
NeuraEventBus.I.emit(const NeuraPulseEvent.wave());
```

## No-crash guarantee
- Missing assets already fall back in the Avatar Support patch.
- This patch ensures **errors become events** and the avatar flips to “error” briefly instead of hard crashing.
- If you *do* want to crash in debug (recommended), `wireGlobalErrorHooks` still forwards to default error behavior in debug.
