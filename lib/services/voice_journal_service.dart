import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../modules/core/app_log.dart';
import '../reliability/safe_boot.dart';
import 'neura_companion_presence.dart';
import 'neura_speech_engine.dart';
import 'neura_speech_to_text_service.dart';

/// Local speech-to-text used by Voice Journal.
///
/// Windows is routed through Neura's native WinRT recognizer because the
/// speech_to_text plugin is not the supported desktop path in this app.
/// Other supported platforms continue to use speech_to_text. Transcript text
/// stays on the local transcript stream and is never copied into presence.
class VoiceJournalService {
  VoiceJournalService() {
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }

  final stt.SpeechToText _stt = stt.SpeechToText();
  final StreamController<String> _pluginTranscriptStream =
      StreamController<String>.broadcast();
  final StreamController<NeuraSpeechSegment> _pluginSegmentStream =
      StreamController<NeuraSpeechSegment>.broadcast();
  final ValueNotifier<bool> _recording = ValueNotifier(false);
  StreamController<String>? _nativeTranscriptStream;
  StreamSubscription<String>? _nativeTranscriptSubscription;

  bool get _usesNativeWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  NeuraSpeechToTextService get _native => NeuraSpeechToTextService.instance;

  String _current = '';
  bool _pluginListening = false;
  bool _disposed = false;
  int _startGeneration = 0;
  NeuraPresenceLease? _presenceLease;
  DateTime? _lastPluginFinalAtUtc;

  Stream<String> get transcriptStream => _usesNativeWindows
      ? _nativeTranscriptController().stream
      : _pluginTranscriptStream.stream;
  Stream<NeuraSpeechSegment> get segmentStream =>
      _usesNativeWindows ? _native.segmentStream : _pluginSegmentStream.stream;

  ValueListenable<bool> get recording => _recording;

  bool get isListening =>
      _usesNativeWindows ? _native.isListening : _pluginListening;

  bool get listeningAllowed => !SafeBoot.instance.safeMode.value;

  StreamController<String> _nativeTranscriptController() {
    final existing = _nativeTranscriptStream;
    if (existing != null) return existing;

    late final StreamController<String> controller;
    controller = StreamController<String>.broadcast(
      onListen: () {
        _nativeTranscriptSubscription ??= _native.transcriptStream.listen(
          (text) {
            if (_isSpeechStatusMessage(text) && !_native.isListening) {
              _markRecordingStopped();
            }
            controller.add(text);
          },
          onError: controller.addError,
          onDone: () {
            unawaited(controller.close());
          },
        );
      },
      onCancel: () async {
        if (controller.hasListener) return;
        await _nativeTranscriptSubscription?.cancel();
        _nativeTranscriptSubscription = null;
      },
    );
    _nativeTranscriptStream = controller;
    return controller;
  }

  Future<bool> startRecording() async {
    if (_disposed || !listeningAllowed) return false;
    final generation = ++_startGeneration;

    if (_usesNativeWindows) {
      final started = await _native.startRecording();
      if (!started || !_canCompleteStart(generation)) {
        if (started) await _native.stopRecording();
        _markRecordingStopped();
        return false;
      }
      if (!_markRecordingStarted()) {
        await _native.stopRecording();
        return false;
      }
      return true;
    }
    if (_pluginListening) return _markRecordingStarted();

    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      final permission = await Permission.microphone.request();
      if (!_canCompleteStart(generation)) return false;
      if (!permission.isGranted) {
        _pluginTranscriptStream.add(
          permission.isPermanentlyDenied
              ? 'Microphone access is disabled. Enable it in system settings.'
              : 'Microphone permission is required for voice journaling.',
        );
        return false;
      }
    }

    try {
      final available = await _stt.initialize(
        onError: (error) {
          _pluginListening = false;
          _markRecordingStopped();
          _pluginTranscriptStream.add(
            'Speech-to-text error: ${error.errorMsg}',
          );
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _pluginListening = false;
            _markRecordingStopped();
          }
        },
      );
      if (!_canCompleteStart(generation)) return false;
      if (!available) {
        _pluginTranscriptStream.add(
          'Speech-to-text is not available on this device.',
        );
        return false;
      }

      _current = '';
      _lastPluginFinalAtUtc = null;
      _pluginListening = true;
      await _stt.listen(
        onResult: (result) {
          if (_disposed || !listeningAllowed || !_pluginListening) return;
          _current = result.recognizedWords;
          _pluginTranscriptStream.add(_current);
          final observedAtUtc = DateTime.now().toUtc();
          final pauseBefore =
              result.finalResult && _lastPluginFinalAtUtc != null
                  ? observedAtUtc.difference(_lastPluginFinalAtUtc!)
                  : Duration.zero;
          final confidence = result.confidence >= 0 && result.confidence <= 1
              ? result.confidence
              : null;
          _pluginSegmentStream.add(
            NeuraSpeechSegment(
              engineId: 'platform_speech_to_text',
              text: _current,
              isFinal: result.finalResult,
              confidence: confidence,
              pauseBefore: pauseBefore,
              observedAtUtc: observedAtUtc,
            ),
          );
          if (result.finalResult) _lastPluginFinalAtUtc = observedAtUtc;
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
      );
      if (!_canCompleteStart(generation)) {
        _pluginListening = false;
        await _stt.cancel();
        _markRecordingStopped();
        return false;
      }
      if (!_pluginListening || !_markRecordingStarted()) {
        _pluginListening = false;
        await _stt.cancel();
        _markRecordingStopped();
        return false;
      }
      return true;
    } catch (error, stack) {
      _pluginListening = false;
      _markRecordingStopped();
      await AppLog.instance.caught('voice_journal_start_failed', error, stack);
      if (!_disposed) {
        _pluginTranscriptStream.add(
          'Speech-to-text could not start on this device.',
        );
      }
      return false;
    }
  }

  bool _canCompleteStart(int generation) =>
      !_disposed && listeningAllowed && generation == _startGeneration;

  bool _markRecordingStarted() {
    if (_disposed || !listeningAllowed) return false;
    _presenceLease ??= NeuraCompanionPresence.instance.acquireListening();
    if (_presenceLease == null) return false;
    if (!_recording.value) _recording.value = true;
    return true;
  }

  void _markRecordingStopped() {
    _presenceLease?.release();
    _presenceLease = null;
    if (_recording.value) _recording.value = false;
  }

  Future<String> stopRecording() async {
    if (_usesNativeWindows) {
      try {
        return await _native.stopRecording();
      } finally {
        _markRecordingStopped();
      }
    }
    if (!_pluginListening) {
      _markRecordingStopped();
      return _current;
    }

    _pluginListening = false;
    _markRecordingStopped();
    try {
      await _stt.stop();
    } catch (error, stack) {
      await AppLog.instance.caught('voice_journal_stop_failed', error, stack);
    }
    return _current;
  }

  void _onSafeModeChanged() {
    if (!listeningAllowed) {
      _startGeneration++;
      _markRecordingStopped();
      if (isListening) unawaited(stopRecording());
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _startGeneration++;
    SafeBoot.instance.safeMode.removeListener(_onSafeModeChanged);
    _markRecordingStopped();

    if (_usesNativeWindows) {
      await _native.stopRecording();
    } else {
      _pluginListening = false;
      await _stt.cancel();
    }
    await _nativeTranscriptSubscription?.cancel();
    await _pluginTranscriptStream.close();
    await _pluginSegmentStream.close();
    await _nativeTranscriptStream?.close();
  }

  static bool _isSpeechStatusMessage(String text) =>
      text.startsWith('Microphone ') || text.startsWith('Speech-to-text ');
}
