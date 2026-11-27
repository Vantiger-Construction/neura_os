import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../profiles/local_profile_service.dart';
import '../reliability/safe_boot.dart';
import 'neura_companion_presence.dart';
import 'neura_local_speech_input.dart';
import 'neura_onnx_int4_speech_engine.dart';
import 'neura_speech_engine.dart';
import 'neura_speech_input.dart';
import 'neura_spoken_meaning.dart';

/// Chat voice through the operator-installed Sherpa-ONNX streaming model.
///
/// This adapter exists only when the Windows build was configured with
/// `NEURA_ENABLE_WINDOWS_ON_DEVICE_ASR=ON` and the person set
/// `NEURA_ON_DEVICE_ASR_ENABLE=1` with a verified local model directory; the
/// engine reports unavailable otherwise and [NeuraVoiceInputRouter] keeps the
/// existing local SAPI recognizer. Audio never leaves the device.
///
/// The native prototype has no foreground-window check of its own, so this
/// adapter stops capture whenever the app leaves the foreground, Safe Mode or
/// a restart requirement turns on, or a profile session is active.
class NeuraOnDeviceSpeechInput
    with WidgetsBindingObserver
    implements NeuraSpeechInput {
  NeuraOnDeviceSpeechInput({
    NeuraSpeechEngine? engine,
    bool Function()? foreground,
    this.silenceWindow = const Duration(seconds: 20),
  })  : _engine = engine ?? NeuraOnnxInt4SpeechEngine(),
        _foreground = foreground {
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafetyChanged);
    SafeBoot.instance.restartRequired.addListener(_onSafetyChanged);
  }

  final NeuraSpeechEngine _engine;
  final bool Function()? _foreground;

  /// Ends a listening turn in which nothing at all was heard, like the SAPI
  /// recognizer's own window, so the microphone does not stay open forever.
  final Duration silenceWindow;

  final _transcripts = StreamController<String>.broadcast();
  final _finals = StreamController<String>.broadcast();
  final _statuses = StreamController<String>.broadcast();
  StreamSubscription<NeuraSpeechSegment>? _segmentSub;
  NeuraPresenceLease? _presence;
  Timer? _silence;
  bool _listening = false;
  bool _disposed = false;
  int _generation = 0;
  String _committed = '';
  String _partial = '';

  String? _lastFailure;
  String? get lastFailure => _lastFailure;

  String get engineId => _engine.id;

  static bool _lifecycleForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  String? get _blockedReason {
    if (_disposed) return 'disposed';
    if (LocalProfileService.instance.enabled) return 'profile_mode';
    if (SafeBoot.instance.safeMode.value) return 'safe_mode';
    if (SafeBoot.instance.restartRequired.value) return 'restart_required';
    if (!(_foreground?.call() ?? _lifecycleForeground())) return 'background';
    return null;
  }

  @override
  Stream<String> get transcriptStream => _transcripts.stream;
  @override
  Stream<String> get finalPhraseStream => _finals.stream;
  @override
  Stream<String> get statusStream => _statuses.stream;
  @override
  bool get isListening => _listening;

  Future<bool> isAvailable() async {
    if (_blockedReason != null) return false;
    try {
      return await _engine.isAvailable();
    } catch (_) {
      return false;
    }
  }

  String get _text {
    final parts = [_committed, _partial].where((part) => part.isNotEmpty);
    return NeuraSpokenText.normalize(parts.join(' '));
  }

  @override
  Future<bool> startRecording() async {
    final blocked = _blockedReason;
    if (blocked != null) {
      _lastFailure = blocked;
      return false;
    }
    if (_listening) return true;
    final generation = ++_generation;
    _lastFailure = null;
    _committed = '';
    _partial = '';
    await _segmentSub?.cancel();
    _segmentSub = _engine.segments.listen((segment) {
      // The generation alone gates delivery: a segment may arrive between the
      // native start acknowledgement and [_listening] being set.
      if (generation != _generation || _blockedReason != null) return;
      _onSegment(segment, generation);
    });
    final started = await _engine.start();
    if (generation != _generation || _blockedReason != null) {
      if (started) await _engine.stop();
      _lastFailure ??= _blockedReason ?? 'superseded';
      return false;
    }
    if (!started) {
      _lastFailure = 'no_local_engine';
      await _segmentSub?.cancel();
      _segmentSub = null;
      return false;
    }
    _listening = true;
    _presence = NeuraCompanionPresence.instance.acquireListening();
    _armSilence(generation);
    return true;
  }

  void _onSegment(NeuraSpeechSegment segment, int generation) {
    _silence?.cancel();
    if (segment.isFinal) {
      final text = segment.text.trim();
      if (text.isNotEmpty) {
        _committed = _committed.isEmpty ? text : '$_committed $text';
      }
      _partial = '';
    } else {
      _partial = segment.text.trim();
    }
    final visible = _text;
    if (visible.isNotEmpty) _transcripts.add(visible);
    if (segment.isFinal && visible.isNotEmpty) {
      _finals.add(visible);
    } else {
      _armSilence(generation);
    }
  }

  void _armSilence(int generation) {
    _silence?.cancel();
    if (_committed.isNotEmpty || _partial.isNotEmpty) return;
    _silence = Timer(silenceWindow, () {
      if (generation != _generation || !_listening) return;
      unawaited(stopRecording().then((_) {
        if (!_disposed && _blockedReason == null) {
          _statuses.add(NeuraLocalSpeechInput.silenceEnded);
        }
      }));
    });
  }

  @override
  Future<String> stopRecording() async {
    _generation++;
    final wasListening = _listening;
    final shown = _text;
    _listening = false;
    _silence?.cancel();
    _silence = null;
    _presence?.release();
    _presence = null;
    await _segmentSub?.cancel();
    _segmentSub = null;
    if (!wasListening && !_engine.isListening) return '';
    final stopped = NeuraSpokenText.normalize(await _engine.stop());
    if (_blockedReason != null) return '';
    // The native stop flushes the tail; prefer it, else what was shown.
    return stopped.isNotEmpty ? stopped : shown;
  }

  void _onSafetyChanged() {
    if (_blockedReason != null) unawaited(stopRecording());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(stopRecording());
  }

  Future<void> shutdownForDataWipe() async {
    await stopRecording().timeout(const Duration(seconds: 3));
  }

  @visibleForTesting
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafetyChanged);
    SafeBoot.instance.restartRequired.removeListener(_onSafetyChanged);
    await stopRecording();
    final engine = _engine;
    if (engine is NeuraOnnxInt4SpeechEngine) await engine.dispose();
    await _transcripts.close();
    await _finals.close();
    await _statuses.close();
  }
}
