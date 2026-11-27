import 'dart:async';
import '../profiles/local_profile_service.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../reliability/safe_boot.dart';
import 'neura_companion_presence.dart';
import 'neura_language.dart';
import 'neura_language_prefs.dart';
import 'neura_speech_input.dart';

/// Chat voice uses an explicitly local native recognizer. This channel has
/// no WinRT dictation, platform default recognizer, model download or fallback.
class NeuraLocalSpeechInput
    implements NeuraSpeechInput, NeuraSpeechLanguageSource {
  NeuraLocalSpeechInput({
    MethodChannel channel = const MethodChannel('neura/local_speech_input'),
    Future<bool> Function()? requestPermission,
    bool Function()? foreground,
    String? Function()? language,
  })  : _channel = channel,
        _requestPermission = requestPermission,
        _foreground = foreground,
        _language = language ?? _preferredLanguage {
    SafeBoot.instance.safeMode.addListener(_onSafetyChanged);
    SafeBoot.instance.restartRequired.addListener(_onSafetyChanged);
  }

  static final NeuraLocalSpeechInput instance = NeuraLocalSpeechInput();
  final MethodChannel _channel;
  final Future<bool> Function()? _requestPermission;
  final bool Function()? _foreground;

  /// The listening language to request, or null for the installed default.
  final String? Function() _language;
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
  String? _heardLanguage;
  String? _requestedLanguage;

  static String? _preferredLanguage() =>
      NeuraLanguagePrefs.instance.listeningCode;

  /// The language of the engine that heard this turn, when it said so.
  @override
  String? get heardLanguage => _heardLanguage;

  /// The language most recently asked for, so a failure can name it.
  NeuraLanguage? get requestedLanguage =>
      NeuraLanguage.fromCode(_requestedLanguage);

  String? _lastFailure;

  /// Why the most recent [startRecording] returned false, as a short fixed
  /// code (never audio or transcript text). Null after a successful start.
  String? get lastFailure => _lastFailure;
  bool get shutdownUnconfirmed => _quarantined;
  static const silenceEnded =
      'No speech detected. The local recognition window ended.';

  /// The recognizer ended its own listening window after an utterance.
  static const listeningStopped =
      'Local listening stopped. Tap the microphone to resume.';

  /// The recognizer doubted what it heard. Its words stay in the message box
  /// for the person to correct or send; nothing is sent on their behalf.
  static const unsureHeard =
      "I'm not sure I heard that right. Check the words, then send.";

  /// The on-device recognizer has no pack for the chosen listening language.
  static String languageUnavailable(NeuraLanguage? language) =>
      'Offline speech recognition for '
      '${language?.englishName ?? 'this language'} is not installed on this '
      'device. Add it in your system speech settings, or set Listening '
      'language to Automatic.';

  // Windows may not report a lifecycle state until focus first changes, so
  // an unreported state counts as foreground, as it does everywhere else in
  // the app. The native recognizer still refuses to start unless Neura's
  // window really is the foreground window, and stops when it loses focus.
  static bool _lifecycleForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  bool get _allowed => _blockedReason == null;

  String? get _blockedReason {
    if (_disposed) return 'disposed';
    if (_quarantined) return 'shutdown_unconfirmed';
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
    if (!_allowed) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'isAvailable',
            _languageArguments(_language()),
          ) ==
          true;
    } catch (_) {
      return false;
    }
  }

  static Map<String, Object?>? _languageArguments(String? language) =>
      language == null ? null : {'language': language};

  @override
  Future<bool> startRecording() {
    final blocked = _blockedReason;
    if (blocked != null) {
      _lastFailure = blocked;
      return Future.value(false);
    }
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
    bool current() {
      if (generation != _generation) {
        _lastFailure = 'superseded';
        return false;
      }
      final blocked = _blockedReason;
      if (blocked != null) _lastFailure = blocked;
      return blocked == null;
    }

    var nativeRequested = false;
    _lastFailure = null;
    _heardLanguage = null;
    final language = _language();
    _requestedLanguage = language;
    try {
      final stopping = _stopping;
      if (stopping != null) await stopping;
      if (!current()) return false;
      if (await _channel.invokeMethod<bool>(
            'isAvailable',
            _languageArguments(language),
          ) !=
          true) {
        _lastFailure =
            language == null ? 'no_local_engine' : 'no_language_engine';
        return false;
      }
      if (!current()) return false;
      final permission = _requestPermission;
      final granted = permission != null
          ? await permission()
          : (defaultTargetPlatform != TargetPlatform.android ||
              (await Permission.microphone.request()).isGranted);
      if (!granted) {
        _lastFailure = 'permission_denied';
        return false;
      }
      if (!current()) return false;
      _text = '';
      nativeRequested = true;
      _nativeSession = generation;
      final started = await _channel.invokeMethod<bool>('start', {
            'session': generation,
            if (language != null) 'language': language,
          }) ==
          true;
      if (!started) _lastFailure = 'native_start_refused';
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
    } on PlatformException catch (error) {
      final details = error.details;
      _lastFailure = details is String && _nativeReasons.contains(details)
          ? 'native_$details'
          : 'native_error';
      if (nativeRequested) await _stopNative(generation);
      return false;
    } catch (_) {
      _lastFailure = 'native_error';
      if (nativeRequested) await _stopNative(generation);
      return false;
    }
  }

  // Fixed codes the Windows host may report; anything else is generic.
  static const _nativeReasons = <String>{
    'not_foreground',
    'no_local_engine',
    'no_language_engine',
    'unsupported_language',
    'recognizer',
    'microphone',
    'dictation',
  };

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
      final unsure = packet['final'] == true && packet['unsure'] == true;
      final heard = NeuraLanguage.fromCode(packet['language']?.toString());
      if (heard != null) _heardLanguage = heard.code;
      if (text is String &&
          text.length <= 16384 &&
          !text.codeUnits.any((c) => c == 0 || c == 0x7f)) {
        _text = text;
        if (text.isNotEmpty) {
          _transcripts.add(text);
          // A phrase the recognizer itself doubts is shown, never sent.
          if (packet['final'] == true && !unsure) _finals.add(text);
        }
      }
      if (unsure) {
        await stopRecording();
        if (_allowed && _generation == generation + 1) {
          _statuses.add(unsureHeard);
        }
        return;
      }
      if (packet['listening'] != true && packet['final'] != true) {
        await stopRecording();
        if (_allowed && _generation == generation + 1) {
          _statuses.add(packet['languageUnavailable'] == true
              ? languageUnavailable(requestedLanguage)
              : packet['silenceEnded'] == true
                  ? silenceEnded
                  : listeningStopped);
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
