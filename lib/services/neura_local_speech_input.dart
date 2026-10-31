import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../reliability/safe_boot.dart';
import 'neura_companion_presence.dart';
import 'neura_speech_input.dart';

/// Startup voice uses an explicitly local native recognizer. This channel has
/// no WinRT dictation, platform default recognizer, model download or fallback.
class NeuraLocalSpeechInput implements NeuraSpeechInput {
  NeuraLocalSpeechInput({
    MethodChannel channel = const MethodChannel('neura/local_speech_input'),
    Future<bool> Function()? requestPermission,
    bool Function()? foreground,
  })  : _channel = channel,
        _requestPermission = requestPermission,
        _foreground = foreground {
    SafeBoot.instance.safeMode.addListener(_onSafetyChanged);
    SafeBoot.instance.restartRequired.addListener(_onSafetyChanged);
  }

  static final NeuraLocalSpeechInput instance = NeuraLocalSpeechInput();
  final MethodChannel _channel;
  final Future<bool> Function()? _requestPermission;
  final bool Function()? _foreground;
  final _transcripts = StreamController<String>.broadcast();
  final _finals = StreamController<String>.broadcast();
  final _statuses = StreamController<String>.broadcast();
  Timer? _timer;
  Future<bool>? _starting;
  Future<String>? _stopping;
  NeuraPresenceLease? _presence;
  bool _listening = false;
  bool _polling = false;
  bool _disposed = false;
  bool _quarantined = false;
  int _generation = 0;
  int? _nativeSession;
  String _text = '';

  bool get _allowed =>
      !_disposed &&
      !_quarantined &&
      !SafeBoot.instance.safeMode.value &&
      !SafeBoot.instance.restartRequired.value &&
      (_foreground?.call() ??
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  @override
  Stream<String> get transcriptStream => _transcripts.stream;
  @override
  Stream<String> get finalPhraseStream => _finals.stream;
  @override
  Stream<String> get statusStream => _statuses.stream;
  @override
  bool get isListening => _listening;

  Future<bool> isAvailable() async {
    if (!_allowed) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> startRecording() {
    if (!_allowed) return Future.value(false);
    if (_listening) return Future.value(true);
    final existing = _starting;
    if (existing != null) return existing;
    final generation = ++_generation;
    late final Future<bool> operation;
    operation = _start(generation).whenComplete(() {
      if (identical(_starting, operation)) _starting = null;
    });
    _starting = operation;
    return operation;
  }

  Future<bool> _start(int generation) async {
    bool current() => generation == _generation && _allowed;
    var nativeRequested = false;
    try {
      final stopping = _stopping;
      if (stopping != null) await stopping;
      if (!current()) return false;
      if (await _channel.invokeMethod<bool>('isAvailable') != true ||
          !current()) {
        return false;
      }
      final permission = _requestPermission;
      final granted = permission != null
          ? await permission()
          : (defaultTargetPlatform != TargetPlatform.android ||
              (await Permission.microphone.request()).isGranted);
      if (!granted || !current()) return false;
      _text = '';
      nativeRequested = true;
      _nativeSession = generation;
      final started =
          await _channel.invokeMethod<bool>('start', {'session': generation}) ==
              true;
      if (!started || !current()) {
        await _stopNative(generation);
        return false;
      }
      _listening = true;
      _presence = NeuraCompanionPresence.instance.acquireListening();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        unawaited(_poll(generation));
      });
      return true;
    } catch (_) {
      if (nativeRequested) await _stopNative(generation);
      return false;
    }
  }

  Future<void> _poll(int generation) async {
    if (_polling || !_listening || generation != _generation) return;
    if (!_allowed) {
      await stopRecording();
      return;
    }
    _polling = true;
    try {
      final packet = await _channel
          .invokeMapMethod<String, dynamic>('poll', {'session': generation});
      if (!_allowed || generation != _generation || !_listening) return;
      if (packet == null || packet['session'] != generation) {
        throw StateError('Invalid local speech session.');
      }
      final text = packet['text'];
      if (text is String &&
          text.length <= 16384 &&
          !text.codeUnits.any((c) => c == 0 || c == 0x7f)) {
        _text = text;
        if (text.isNotEmpty) {
          _transcripts.add(text);
          if (packet['final'] == true) _finals.add(text);
        }
      }
      if (packet['listening'] != true && packet['final'] != true) {
        await stopRecording();
        if (!_disposed) {
          _statuses
              .add('Local listening stopped. Tap the microphone to resume.');
        }
      }
    } catch (_) {
      await stopRecording();
      if (!_disposed) _statuses.add('Local speech input is unavailable.');
    } finally {
      _polling = false;
    }
  }

  @override
  Future<String> stopRecording() {
    final session = _generation++;
    final text = _allowed ? _text : '';
    _text = '';
    _listening = false;
    _timer?.cancel();
    _timer = null;
    _presence?.release();
    _presence = null;
    final existing = _stopping;
    if (existing != null) return existing;
    if (_nativeSession == null && _starting == null) return Future.value(text);
    late final Future<String> operation;
    operation = _stopNative(session)
        .then((stopped) =>
            stopped && _allowed && _generation == session + 1 ? text : '')
        .whenComplete(() {
      if (identical(_stopping, operation)) _stopping = null;
    });
    _stopping = operation;
    return operation;
  }

  Future<bool> _stopNative(int session) async {
    try {
      await _channel.invokeMethod<void>('stop', {'session': session});
      if (_nativeSession != null && session >= _nativeSession!) {
        _nativeSession = null;
      }
      return true;
    } catch (_) {
      // Do not return a transcript or start another session if shutdown has
      // not been acknowledged. Native host teardown also releases capture.
      final firstFailure = !_quarantined;
      _quarantined = true;
      if (!_disposed && firstFailure) {
        _statuses.add(
            'Microphone shutdown was not confirmed. Close Neura before retrying voice.');
      }
      return false;
    }
  }

  void _onSafetyChanged() {
    if (!_allowed) unawaited(stopRecording());
  }

  Future<void> shutdownForDataWipe() async {
    await stopRecording().timeout(const Duration(seconds: 3));
    await _starting?.timeout(const Duration(seconds: 3));
    final session = _nativeSession;
    if (session != null) {
      // A failed stop is an incomplete wipe, never a successful shutdown.
      await _channel.invokeMethod<void>('stop', {'session': session});
      _nativeSession = null;
    }
  }

  @visibleForTesting
  Future<void> dispose() async {
    _disposed = true;
    SafeBoot.instance.safeMode.removeListener(_onSafetyChanged);
    SafeBoot.instance.restartRequired.removeListener(_onSafetyChanged);
    await stopRecording();
    await _starting;
    await _transcripts.close();
    await _finals.close();
    await _statuses.close();
  }
}
