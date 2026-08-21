// lib/integrations/tts/neura_flutter_tts_viseme_bridge.dart
//
// Hooks flutter_tts callbacks and emits mouth/viseme events.
// - Safe if progress callbacks are never fired.
// - Safe if you don't have AvatarOrchestrator present.
// - Safe if Rive inputs do not exist.

import 'package:flutter_tts/flutter_tts.dart';

import '../../core/neura_event_bus.dart';
import '../../core/neura_events.dart';
import '../../core/neura_events_extra.dart';
import '../../avatar/viseme/neura_viseme_engine.dart';

class NeuraFlutterTtsVisemeBridge {
  static bool _attached = false;

  /// [onCompletion], [onCancel], and [onError] fire alongside this bridge's
  /// own event-bus emissions -- flutter_tts only supports one handler of
  /// each kind, so callers that also need completion/cancel/error signals
  /// (e.g. to resolve a Dart-side speak() completion future) must go
  /// through these hooks rather than calling setCompletionHandler etc.
  /// themselves, which would silently replace this bridge's handler.
  static Future<void> attach(
    FlutterTts tts, {
    NeuraEventBus? bus,
    void Function()? onCompletion,
    void Function()? onCancel,
    void Function(dynamic message)? onError,
  }) async {
    if (_attached) return;
    _attached = true;

    final b = bus ?? NeuraEventBus.I;

    // Start / completion are the most reliable.
    tts.setStartHandler(() {
      b.emit(const NeuraTalkingEvent(true));
      // default "talking starts": open mouth a bit
      b.emit(const NeuraMouthOpenEvent(0.25));
      b.emit(const NeuraVisemeEvent(NeuraViseme.AI));
    });

    tts.setCompletionHandler(() {
      b.emit(const NeuraTalkingEvent(false));
      b.emit(const NeuraMouthOpenEvent(0.0));
      b.emit(const NeuraVisemeEvent(NeuraViseme.rest));
      // small blink on finish feels alive
      b.emit(const NeuraPulseEvent.blink());
      onCompletion?.call();
    });

    tts.setCancelHandler(() {
      b.emit(const NeuraTalkingEvent(false));
      b.emit(const NeuraMouthOpenEvent(0.0));
      b.emit(const NeuraVisemeEvent(NeuraViseme.rest));
      onCancel?.call();
    });

    tts.setErrorHandler((message) {
      b.emit(const NeuraTalkingEvent(false));
      b.emit(const NeuraMouthOpenEvent(0.0));
      b.emit(const NeuraVisemeEvent(NeuraViseme.rest));
      b.emit(NeuraErrorEvent('TTS error: $message', hint: 'flutter_tts'));
      onError?.call(message);
    });

    // Progress handler gives substring positions in the original text for many platforms.
    // We'll sample a tiny slice and infer a viseme.
    tts.setProgressHandler((String text, int start, int end, String word) {
      try {
        final safeStart = start.clamp(0, text.length);
        final safeEnd = end.clamp(0, text.length);
        String frag;
        if (safeEnd > safeStart) {
          frag = text.substring(safeStart, safeEnd);
        } else if (word.isNotEmpty) {
          frag = word;
        } else {
          frag = text.isEmpty
              ? ''
              : text.substring(
                  safeStart, (safeStart + 1).clamp(0, text.length));
        }

        final v = NeuraVisemeEngine.inferFromFragment(frag);
        final open = NeuraVisemeEngine.mouthOpenFromFragment(frag);
        b.emit(NeuraVisemeEvent(v));
        b.emit(NeuraMouthOpenEvent(open));
      } catch (_) {
        // Never throw from progress callback.
      }
    });
  }
}
