import '../core/neura_event_bus.dart';
import '../core/neura_events.dart';
import 'neura_work_tracker.dart';

/// Dependency-free "real sources" hooks.
///
/// You call these from your STT/TTS/services.
/// They emit typed NeuraEvents that AvatarOrchestrator already understands.
class NeuraSourcesHooks {
  NeuraSourcesHooks._();

  static NeuraEventBus get _bus => NeuraEventBus.I;

  // Ref-counted trackers so overlapping operations behave.
  static final NeuraWorkTracker _thinkingTracker = NeuraWorkTracker(
    onActiveChanged: (active) => _bus.emit(NeuraThinkingEvent(active)),
  );

  static final NeuraWorkTracker _talkingTracker = NeuraWorkTracker(
    onActiveChanged: (active) => _bus.emit(NeuraTalkingEvent(active)),
  );

  static final NeuraWorkTracker _listeningTracker = NeuraWorkTracker(
    onActiveChanged: (active) => _bus.emit(NeuraListeningEvent(active)),
  );

  // Convenience single-tokens for "start/stop" style integrations.
  // If you have overlapping operations (multiple parallel calls),
  // prefer the token-returning begin() methods or track* wrappers.
  static NeuraWorkToken? _sttToken;
  static NeuraWorkToken? _ttsToken;
  static NeuraWorkToken? _thinkingToken;

  /// --- STT ---
  static NeuraWorkToken sttBegin({String? hint}) {
    // hint reserved for future telemetry.
    return _listeningTracker.begin();
  }

  static void sttStart({String? hint}) {
    _sttToken ??= sttBegin(hint: hint);
  }

  static void sttStop() {
    _sttToken?.release();
    _sttToken = null;
  }

  /// --- TTS ---
  static NeuraWorkToken ttsBegin({String? hint}) {
    return _talkingTracker.begin();
  }

  static void ttsStart({String? hint}) {
    _ttsToken ??= ttsBegin(hint: hint);
  }

  static void ttsStop() {
    _ttsToken?.release();
    _ttsToken = null;
  }

  static Future<T> trackTalking<T>(Future<T> Function() fn, {String? hint}) {
    return _talkingTracker.trackFn(fn);
  }

  /// --- "Thinking" / work ---
  static NeuraWorkToken thinkingBegin({String? hint}) {
    return _thinkingTracker.begin();
  }

  static void thinkingStart({String? hint}) {
    _thinkingToken ??= thinkingBegin(hint: hint);
  }

  static void thinkingStop() {
    _thinkingToken?.release();
    _thinkingToken = null;
  }

  static Future<T> trackThinking<T>(Future<T> Function() fn, {String? hint}) {
    return _thinkingTracker.trackFn(fn);
  }

  static Stream<T> trackThinkingStream<T>(Stream<T> stream, {String? hint}) {
    return _thinkingTracker.trackStream(stream);
  }

  /// --- Mood ---
  static void setMood({required double mood, required double energy}) {
    _bus.emit(NeuraMoodEvent(mood: mood, energy: energy));
  }

  /// --- Pulses ---
  static void pulseBlink() => _bus.emit(const NeuraPulseEvent.blink());
  static void pulseWave() => _bus.emit(const NeuraPulseEvent.wave());

  /// --- Errors ---
  static void error(Object error, [StackTrace? stack, String? hint]) {
    _bus.emit(NeuraErrorEvent(error, stack: stack, hint: hint));
  }
}
