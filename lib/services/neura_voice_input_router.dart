import 'dart:async';

import 'package:flutter/foundation.dart';

import 'neura_local_speech_input.dart';
import 'neura_on_device_asr_opt_in.dart';
import 'neura_on_device_speech_input.dart';
import 'neura_speech_input.dart';

/// Chooses the recognizer for each chat listening turn.
///
/// Both candidates are on-device. The Sherpa-ONNX streaming model is used
/// only when it reports available, which requires the person's explicit build
/// flag, runtime opt-in and verified local model directory; otherwise the
/// existing local SAPI recognizer is used exactly as before. There is no
/// cloud recognizer, model download or silent substitution: the choice is
/// visible through [activeEngine] and logged by the chat screen.
class NeuraVoiceInputRouter implements NeuraSpeechInput {
  NeuraVoiceInputRouter({
    NeuraLocalSpeechInput? local,
    NeuraOnDeviceSpeechInput Function()? onDevice,
    bool Function()? optedIn,
  })  : _local = local ?? NeuraLocalSpeechInput.instance,
        _onDeviceFactory = onDevice ?? NeuraOnDeviceSpeechInput.new,
        _optedIn = optedIn ?? neuraOnDeviceAsrOptedIn;

  static final NeuraVoiceInputRouter instance = NeuraVoiceInputRouter();

  final NeuraLocalSpeechInput _local;
  final NeuraOnDeviceSpeechInput Function() _onDeviceFactory;
  final bool Function() _optedIn;
  NeuraOnDeviceSpeechInput? _onDevice;
  NeuraSpeechInput? _active;

  final _transcripts = StreamController<String>.broadcast();
  final _finals = StreamController<String>.broadcast();
  final _statuses = StreamController<String>.broadcast();
  final List<StreamSubscription<String>> _subs = [];

  NeuraOnDeviceSpeechInput get _streaming => _onDevice ??= _onDeviceFactory();

  bool get _usingStreaming {
    final onDevice = _onDevice;
    return onDevice != null && identical(_active, onDevice);
  }

  /// Short, fixed name of the recognizer used for the current or last turn.
  String get activeEngine => _usingStreaming ? 'sherpa' : 'sapi';

  String? get lastFailure {
    if (_usingStreaming) return _onDevice?.lastFailure;
    return _local.lastFailure;
  }

  void _forward(
    Stream<String> from,
    StreamController<String> to,
    NeuraSpeechInput source,
  ) {
    _subs.add(from.listen((text) {
      if (identical(_active, source)) to.add(text);
    }));
  }

  /// Makes [source] the active recognizer and forwards only its events.
  /// Subscriptions are renewed on every turn, in the caller's zone, rather
  /// than kept for the life of this singleton.
  Future<void> _follow(NeuraSpeechInput source) async {
    final previous = List.of(_subs);
    _subs.clear();
    for (final sub in previous) {
      await sub.cancel();
    }
    _active = source;
    _forward(source.transcriptStream, _transcripts, source);
    _forward(source.finalPhraseStream, _finals, source);
    _forward(source.statusStream, _statuses, source);
  }

  @override
  Stream<String> get transcriptStream => _transcripts.stream;
  @override
  Stream<String> get finalPhraseStream => _finals.stream;
  @override
  Stream<String> get statusStream => _statuses.stream;
  @override
  bool get isListening => _active?.isListening ?? false;

  Future<bool> _streamingAvailable() async =>
      _optedIn() && await _streaming.isAvailable();

  Future<bool> isAvailable() async =>
      await _streamingAvailable() || await _local.isAvailable();

  @override
  Future<bool> startRecording() async {
    final active = _active;
    if (active != null && active.isListening) return true;
    if (await _streamingAvailable()) {
      await _follow(_streaming);
      if (await _streaming.startRecording()) return true;
    }
    await _follow(_local);
    return _local.startRecording();
  }

  @override
  Future<String> stopRecording() async {
    final active = _active;
    if (active == null) return _local.stopRecording();
    return active.stopRecording();
  }

  /// Stops both recognizers; used by data wipe and profile boundaries.
  Future<void> shutdownForDataWipe() async {
    final onDevice = _onDevice;
    if (onDevice != null) await onDevice.shutdownForDataWipe();
    await _local.shutdownForDataWipe();
  }

  /// Stops only the streaming recognizer, if it was ever created. The SAPI
  /// recognizer keeps its own, separately reported shutdown step.
  Future<void> shutdownOnDeviceForDataWipe() async {
    final onDevice = _onDevice;
    if (onDevice != null) await onDevice.shutdownForDataWipe();
  }

  @visibleForTesting
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _onDevice?.dispose();
    await _transcripts.close();
    await _finals.close();
    await _statuses.close();
  }
}
