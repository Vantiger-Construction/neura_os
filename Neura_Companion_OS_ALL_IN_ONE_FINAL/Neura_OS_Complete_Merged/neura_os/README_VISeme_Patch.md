# Neura Companion – Viseme / Mouth Sync Patch (Crash-Safe)

This patch adds **talking mouth / viseme-style animation wiring** without hard dependency on any single TTS/STT stack.

## What you get
- `NeuraVisemeEngine`: text → viseme hints (fast heuristic)
- `NeuraFlutterTtsVisemeBridge`: hooks `flutter_tts` progress callbacks and emits viseme + mouth-open events
- `AvatarOrchestrator` additions (optional): listens for viseme/mouth events and drives `AvatarController`
- `AvatarController` additions (safe): optional Rive inputs `mouthOpen` and `viseme` if they exist, ignored if not.

## Asset-side (Rive) – Optional inputs
If your Rive state machine has these inputs, they’ll be driven automatically:
- `mouthOpen` (Number, 0..1)
- `viseme` (Number, recommended 0..14)

If you don’t have them, **nothing breaks**.

## Integration (minimum)
1) Merge this patch into your project root.
2) If you use `flutter_tts`, attach the bridge once during init:

```dart
final tts = FlutterTts();
await NeuraFlutterTtsVisemeBridge.attach(tts);
```

That’s it — viseme events will flow through `NeuraEventBus` and the `AvatarOrchestrator` will animate if present.

## If you don’t use flutter_tts
You can still emit events manually:

```dart
NeuraEventBus.I.emit(NeuraMouthOpenEvent(0.6));
NeuraEventBus.I.emit(NeuraVisemeEvent(NeuraViseme.AH));
```

## Notes
- This is **not** phoneme-perfect (that requires a TTS/phoneme stream). It’s a robust “alive factor” layer.
- Designed to be safe even if you rename artboards/state machines/inputs.
