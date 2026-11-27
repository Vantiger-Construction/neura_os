import 'dart:async';

import 'package:flutter/foundation.dart';

import 'neura_local_speech_input.dart';
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
  })  : _local = local ?? NeuraLocalSpeechInput.instance,
        _onDeviceFactory = onDevice ?? NeuraOnDeviceSpeechInput.new;

  static final NeuraVoiceInputRouter instance = NeuraVoiceInputRouter();

  final NeuraLocalSpeechInput _local;
  final NeuraOnDeviceSpeechInput Function() _onDeviceFactory;
  NeuraOnDeviceSpeechInput? _onDevice;
  NeuraSpeechInput? _active;

  final _transcripts = StreamController<String>.broadcast();
  final _finals = StreamController<String>.broadcast();
  final _statuses = StreamController<String>.broadcast();
  final List<StreamSubscription<String>> _subs = [];
  bool _wired = false;

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

  void _wire() {
    if (_wired) return;
    _wired = true;
    for (final source in <NeuraSpeechInput>[_local, _streaming]) {
      _forward(source.transcriptStream, _transcripts, source);
      _forward(source.finalPhraseStream, _finals, source);
      _forward(source.statusStream, _statuses, source);
    }
  }

  @override
  Stream<String> get transcriptStream => _transcripts.stream;
  @override
  Stream<String> get finalPhraseStream => _finals.stream;
  @override
  Stream<String> get statusStream => _statuses.stream;
  @override
  bool get isListening => _active?.isListening ?? false;

  Future<bool> isAvailable() async =>
      await _streaming.isAvailable() || await _local.isAvailable();

  @override
  Future<bool> startRecording() async {
    _wire();
    final active = _active;
    if (active != null && active.isListening) return true;
    if (await _streaming.isAvailable()) {
      _active = _streaming;
      if (await _streaming.startRecording()) return true;
    }
    _active = _local;
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
