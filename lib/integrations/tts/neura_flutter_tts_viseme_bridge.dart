// lib/integrations/tts/neura_flutter_tts_viseme_bridge.dart
//
// Hooks flutter_tts callbacks and emits mouth/viseme events.
// - Safe if progress callbacks are never fired.
// - Safe if you don't have AvatarOrchestrator present.
// - Safe if Rive inputs do not exist.

import 'package:flutter_tts/flutter_tts.dart';

import '../../avatar/viseme/neura_viseme_engine.dart';
import '../../core/neura_event_bus.dart';
import '../../core/neura_events.dart';
import '../../core/neura_events_extra.dart';

class NeuraFlutterTtsVisemeBridge {
  static bool _attached = false;

  /// [onCompletion], [onCancel], and [onError] run alongside the bridge's
  /// event-bus emissions. flutter_tts supports only one handler of each kind,
  /// so services that also need lifecycle signals must use these hooks instead
  /// of replacing the bridge's handlers.
  static Future<void> attach(
    FlutterTts tts, {
    NeuraEventBus? bus,
    void Function()? onCompletion,
    void Function()? onCancel,
    void Function(dynamic message)? onError,
  }) async {
    if (_attached) return;

    final b = bus ?? NeuraEventBus.I;

    // Start / completion are the most reliable.
    tts.setStartHandler(() {
      b.emit(const NeuraTalkingEvent(true));
      // Default "talking starts": open mouth a bit.
      b.emit(const NeuraMouthOpenEvent(0.25));
      b.emit(const NeuraVisemeEvent(NeuraViseme.AI));
    });

    tts.setCompletionHandler(() {
      b.emit(const NeuraTalkingEvent(false));
      b.emit(const NeuraMouthOpenEvent(0.0));
      b.emit(const NeuraVisemeEvent(NeuraViseme.rest));
      // A small blink on finish feels alive.
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

    // Progress gives substring positions in the original text on many
    // platforms. Sample a small fragment and infer a viseme.
    tts.setProgressHandler((String text, int start, int end, String word) {
      try {
        final safeStart = start.clamp(0, text.length);
        final safeEnd = end.clamp(0, text.length);
        String fragment;
        if (safeEnd > safeStart) {
          fragment = text.substring(safeStart, safeEnd);
        } else if (word.isNotEmpty) {
          fragment = word;
        } else {
          fragment = text.isEmpty
              ? ''
              : text.substring(
                  safeStart,
                  (safeStart + 1).clamp(0, text.length),
                );
        }

        final viseme = NeuraVisemeEngine.inferFromFragment(fragment);
        final open = NeuraVisemeEngine.mouthOpenFromFragment(fragment);
        b.emit(NeuraVisemeEvent(viseme));
        b.emit(NeuraMouthOpenEvent(open));
      } catch (_) {
        // Never throw from a native progress callback.
      }
    });

    // Mark attached only after every callback registration succeeds so a
    // transient plugin failure can be retried later in this process.
    _attached = true;
  }
}
