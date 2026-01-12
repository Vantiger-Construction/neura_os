# Neura Companion Patch — Wire NeuraEventBus to Real Sources

This patch adds a **crash-safe “signal bridge” layer** so your real runtime systems (STT, TTS, async work, API calls) can drive the Neura avatar automatically.

## What you get
- **NeuraSourcesHooks**: tiny, dependency-free hooks you can call from anywhere.
- **Ref-counted signals**: overlapping work/voice won’t flicker on/off.
- Optional bridges for common plugins:
  - `speech_to_text` (STT)
  - `flutter_tts` (TTS)

> Important: The optional bridges import those packages. Only import those bridge files if you have the packages in `pubspec.yaml`.

---

## 1) Merge patch
Copy these files into your project (merge folders):
- `lib/integrations/neura_sources_hooks.dart`
- `lib/integrations/neura_work_tracker.dart`
- `lib/integrations/stt/neura_speech_to_text_bridge.dart` (optional)
- `lib/integrations/tts/neura_flutter_tts_bridge.dart` (optional)

Then:
```bash
flutter pub get
```

---

## 2) Wire to Speech-to-Text (STT)
### If you already have an STT service
Just add hooks in your start/stop:

```dart
import 'integrations/neura_sources_hooks.dart';

Future<void> startListening() async {
  NeuraSourcesHooks.sttStart();
  try {
    // your existing STT start
  } catch (e, st) {
    NeuraSourcesHooks.error(e, st, hint: 'STT startListening');
  }
}

Future<void> stopListening() async {
  try {
    // your existing STT stop
  } finally {
    NeuraSourcesHooks.sttStop();
  }
}
```

### If you want a ready-made bridge (requires `speech_to_text`)
```dart
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'integrations/stt/neura_speech_to_text_bridge.dart';

final speech = stt.SpeechToText();
final bridge = NeuraSpeechToTextBridge(speech);
await bridge.initialize();
await bridge.listen();
```

---

## 3) Wire to Text-to-Speech (TTS)
### If you already have a TTS service
Add hooks when speaking starts/stops:

```dart
import 'integrations/neura_sources_hooks.dart';

Future<void> speak(String text) async {
  return NeuraSourcesHooks.trackTalking(
    () async {
      // your existing TTS call
    },
    hint: 'TTS speak',
  );
}
```

### If you want a ready-made bridge (requires `flutter_tts`)
```dart
import 'package:flutter_tts/flutter_tts.dart';
import 'integrations/tts/neura_flutter_tts_bridge.dart';

final tts = FlutterTts();
await NeuraFlutterTtsBridge(tts).attach();
```

---

## 4) Wire “thinking” to real async work (API calls, DB, long tasks)
Wrap ANY Future:

```dart
import 'integrations/neura_sources_hooks.dart';

final result = await NeuraSourcesHooks.trackThinking(
  () => myApi.call(),
  hint: 'OpenAI call',
);
```

Or manual begin/end if you need it:

```dart
final token = NeuraSourcesHooks.thinkingBegin(hint: 'Sync job');
try {
  await doWork();
} finally {
  token.release();
}
```

---

## 5) Emit mood/energy from real signals (optional)
If you compute mood/energy elsewhere:

```dart
NeuraSourcesHooks.setMood(mood: 0.2, energy: 0.7);
```

---

## Common gotcha
If your avatar doesn’t react, confirm you already have:
- `AvatarOrchestrator` started and listening to `NeuraEventBus.I`.
- `GlobalAvatarHost` wrapped around the app.

(Those come from the previous patch.)
