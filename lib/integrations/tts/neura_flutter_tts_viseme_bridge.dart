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
  static final _attached = Expando<bool>();

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
    if (_attached[tts] == true) return;

    final eventBus = bus ?? NeuraEventBus.I;

    tts.setStartHandler(() {
      eventBus.emit(const NeuraTalkingEvent(true));
      eventBus.emit(const NeuraMouthOpenEvent(0.25));
      eventBus.emit(const NeuraVisemeEvent(NeuraViseme.AI));
    });

    tts.setCompletionHandler(() {
      _emitRestState(eventBus);
      eventBus.emit(const NeuraPulseEvent.blink());
      onCompletion?.call();
    });

    tts.setCancelHandler(() {
      _emitRestState(eventBus);
      onCancel?.call();
    });

    tts.setErrorHandler((message) {
      _emitRestState(eventBus);
      eventBus.emit(
        NeuraErrorEvent(
          'TTS error: $message',
          hint: 'flutter_tts',
        ),
      );
      onError?.call(message);
    });

    // Many platforms report the spoken substring through this callback. Keep
    // every index inside the source text before deriving the current viseme.
    tts.setProgressHandler((String text, int start, int end, String word) {
      try {
        final safeStart = start.clamp(0, text.length).toInt();
        final safeEnd = end.clamp(0, text.length).toInt();
        final fragment = _extractFragment(
          text: text,
          start: safeStart,
          end: safeEnd,
          word: word,
        );

        final viseme = NeuraVisemeEngine.inferFromFragment(fragment);
        final open = NeuraVisemeEngine.mouthOpenFromFragment(fragment);
        eventBus.emit(NeuraVisemeEvent(viseme));
        eventBus.emit(NeuraMouthOpenEvent(open));
      } catch (_) {
        // Native progress callbacks must never propagate an exception.
      }
    });

    // Mark attached only after every callback registration succeeds so a
    // transient plugin failure can be retried later in this process.
    _attached[tts] = true;
  }

  static void _emitRestState(NeuraEventBus bus) {
    bus.emit(const NeuraTalkingEvent(false));
    bus.emit(const NeuraMouthOpenEvent(0.0));
    bus.emit(const NeuraVisemeEvent(NeuraViseme.rest));
  }

  static String _extractFragment({
    required String text,
    required int start,
    required int end,
    required String word,
  }) {
    if (text.isEmpty) return word;

    if (end > start) {
      return text.substring(start, end);
    }

    if (word.isNotEmpty) return word;
    if (start >= text.length) return '';

    final nextIndex = (start + 1).clamp(0, text.length).toInt();
    if (nextIndex <= start) return '';

    return text.substring(start, nextIndex);
  }
}
