import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../integrations/tts/neura_flutter_tts_viseme_bridge.dart';
import '../integrations/tts/neura_windows_tts.dart';
import 'neura_audio_focus.dart';
import 'neura_companion_presence.dart';
import '../reliability/safe_boot.dart';
import '../startup/neura_prefs_cache.dart';

/// One installed voice, as surfaced by the platform speech adapter.
class NeuraVoiceOption {
  final String name;
  final String locale;
  final String gender;

  const NeuraVoiceOption({
    required this.name,
    required this.locale,
    required this.gender,
  });
}

enum NeuraReplySpeechMode { off, afterComplete, streamed }

extension NeuraReplySpeechModeLabel on NeuraReplySpeechMode {
  String get label => switch (this) {
        NeuraReplySpeechMode.off => 'Off',
        NeuraReplySpeechMode.afterComplete => 'After reply',
        NeuraReplySpeechMode.streamed => 'As it arrives',
      };

  String get description => switch (this) {
        NeuraReplySpeechMode.off => 'Never speak chat replies automatically.',
        NeuraReplySpeechMode.afterComplete =>
          'Wait for the complete reply, then speak it.',
        NeuraReplySpeechMode.streamed =>
          'Start speaking completed phrases while the reply streams.',
      };
}

/// Speaks Neura's chat replies aloud. Wires the existing
/// [NeuraFlutterTtsVisemeBridge] so avatar mouth/viseme events fire on the
/// Neura event bus alongside actual speech.
class NeuraTtsService with WidgetsBindingObserver {
  NeuraTtsService._()
      : _nativeCommandTimeout = const Duration(seconds: 10),
        _speechTimeout = const Duration(minutes: 2) {
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }

  @visibleForTesting
  NeuraTtsService.forTesting(
    FlutterTts tts, {
    Duration nativeCommandTimeout = const Duration(seconds: 10),
    Duration speechTimeout = const Duration(minutes: 2),
  })  : _tts = tts,
        _nativeCommandTimeout = nativeCommandTimeout,
        _speechTimeout = speechTimeout {
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }

  static final NeuraTtsService instance = NeuraTtsService._();

  static const _kVoiceNameKey = 'neura.tts.voice_name';
  static const _kVoiceLocaleKey = 'neura.tts.voice_locale';
  static const _kSpeechRateKey = 'neura.tts.speech_rate';
  static const _kPitchKey = 'neura.tts.pitch';
  static const _kVolumeKey = 'neura.tts.volume';
  static const _kReplySpeechModeKey = 'neura.tts.reply_speech_mode.v1';
  static const _kLegacySpeakRepliesKey = 'neura.tts.speak_replies';

  FlutterTts? _tts;
  final Duration _nativeCommandTimeout;
  final Duration _speechTimeout;
  Future<bool>? _initialization;
  bool _initialized = false;
  bool enabled = true;
  String? _selectedVoiceName;
  Future<void>? _nativeTail;
  _TtsPlayback? _playing;
  bool _acceptCallbacks = false;
  bool _nativeUncertain = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _observingLifecycle = false;
  Future<void>? _disposal;
  int _speechGeneration = 0;
  int _cancelGeneration = 0;
  double _speechRate = 0.5;
  double _pitch = 1.05;
  double _volume = 1.0;
  NeuraReplySpeechMode _replySpeechMode = NeuraReplySpeechMode.off;

  bool get playbackAllowed =>
      !_disposed && _foreground && !SafeBoot.instance.safeMode.value;

  void _observeLifecycle() {
    if (_observingLifecycle) return;
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _observingLifecycle = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(stop().catchError((_) {}));
  }

  bool get _engineUsable => playbackAllowed && !_nativeUncertain;

  /// The currently active voice's display name, or null before initialization
  /// or when no voice has been explicitly selected.
  String? get selectedVoiceName => _selectedVoiceName;
  double get speechRate => _speechRate;
  double get pitch => _pitch;
  double get volume => _volume;

  /// The explicit automatic speech policy for chat replies. Reading this
  /// value never forces the native TTS engine to initialize.
  NeuraReplySpeechMode get replySpeechMode {
    final prefs = NeuraPrefsCache.prefsOrNull;
    final saved = prefs?.getString(_kReplySpeechModeKey);
    if (saved != null) {
      return NeuraReplySpeechMode.values.firstWhere(
        (mode) => mode.name == saved,
        orElse: () => NeuraReplySpeechMode.off,
      );
    }

    // Preserve existing opt-ins from the former boolean setting. A missing or
    // false legacy value remains off, which is the privacy-safe default.
    if (prefs?.getBool(_kLegacySpeakRepliesKey) == true) {
      return NeuraReplySpeechMode.streamed;
    }
    return _replySpeechMode;
  }

  /// Compatibility surface for existing callers. New UI should use
  /// [replySpeechMode] and [setReplySpeechMode].
  bool get speakRepliesEnabled => replySpeechMode != NeuraReplySpeechMode.off;

  Future<void> setReplySpeechMode(NeuraReplySpeechMode mode) async {
    _replySpeechMode = mode;
    try {
      final prefs = NeuraPrefsCache.prefs;
      await prefs.setString(_kReplySpeechModeKey, mode.name);
      await prefs.setBool(
        _kLegacySpeakRepliesKey,
        mode != NeuraReplySpeechMode.off,
      );
    } catch (_) {
      // The in-memory value above still applies for this session.
    }
  }

  Future<void> setSpeakRepliesEnabled(bool value) => setReplySpeechMode(
        value ? NeuraReplySpeechMode.streamed : NeuraReplySpeechMode.off,
      );

  /// Forces the native TTS engine to initialize without speaking anything.
  Future<void> warmUp() async {
    await _ensureInit();
  }

  Future<bool> _ensureInit() {
    if (!_engineUsable) return Future<bool>.value(false);
    // Reading voice preferences and Safe Mode no-ops must stay usable before
    // any UI binding or native speech engine exists.
    _observeLifecycle();
    if (!_engineUsable) return Future<bool>.value(false);
    if (_initialized) return Future<bool>.value(true);

    final existing = _initialization;
    if (existing != null) return existing;

    late final Future<bool> operation;
    operation = _initialize().timeout(
      _nativeCommandTimeout,
      onTimeout: () {
        _nativeUncertain = true;
        throw TimeoutException('Local speech initialization timed out.');
      },
    ).whenComplete(() {
      if (identical(_initialization, operation)) {
        _initialization = null;
      }
    });
    _initialization = operation;
    return operation;
  }

  Future<bool> _initialize() async {
    final generation = _cancelGeneration;
    bool current() => _engineUsable && generation == _cancelGeneration;
    if (!current()) return false;

    final tts = _tts ??=
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows
            ? NeuraWindowsTts()
            : FlutterTts());
    await NeuraFlutterTtsVisemeBridge.attach(
      tts,
      onCompletion: _completeSpeak,
      onCancel: _completeSpeak,
      onError: (_) => _completeSpeak(error: StateError('Local speech failed.')),
      playbackAllowed: () => _acceptCallbacks && _engineUsable,
    );

    if (!current()) return false;

    // Keep native awaitSpeakCompletion disabled (issue #32 / PR #41).
    // Windows uses Neura's owned SAPI channel instead of the plugin's synthesis
    // coroutine. Other platforms retain the Dart callback completion bridge.
    // Physical Windows crash acceptance remains unverified.
    // See docs/WINDOWS_TTS_RELIABILITY.md.
    final prefs = NeuraPrefsCache.prefsOrNull;
    _speechRate = (prefs?.getDouble(_kSpeechRateKey) ?? 0.5).clamp(0.25, 0.75);
    _pitch = (prefs?.getDouble(_kPitchKey) ?? 1.05).clamp(0.5, 2.0);
    _volume = (prefs?.getDouble(_kVolumeKey) ?? 1.0).clamp(0.0, 1.0);
    await tts.setSpeechRate(_speechRate);
    if (!current()) return false;
    await tts.setPitch(_pitch);
    if (!current()) return false;
    await tts.setVolume(_volume);
    if (!current()) return false;
    await _applySavedOrDefaultVoice(generation);
    if (!current()) return false;

    _initialized = true;
    return true;
  }

  void _completeSpeak({Object? error}) {
    if (_acceptCallbacks) _finish(_playing, error: error);
  }

  void _finish(_TtsPlayback? playback, {Object? error, StackTrace? stack}) {
    if (playback == null || playback.done.isCompleted) return;
    playback.deadline?.cancel();
    playback.focus?.release();
    playback.presence?.release();
    if (identical(_playing, playback)) {
      _playing = null;
      _acceptCallbacks = false;
      NeuraFlutterTtsVisemeBridge.reset(_tts);
    }
    if (error == null) {
      playback.done.complete();
    } else {
      playback.done.completeError(error, stack ?? StackTrace.current);
    }
  }

  // Serialize only native command dispatch/acknowledgement, not the whole
  // utterance. A replacement can stop playback while its Dart caller waits.
  Future<void> _queueNative(Future<void> Function() action) {
    // Create an idle tail in the caller's zone. A constructor-created future
    // can retain an unrelated scheduler, including a previous widget clock.
    final next = (_nativeTail ?? Future<void>.value()).then((_) async {
      if (_nativeUncertain) {
        throw StateError('Local speech requires an application restart.');
      }
      await action().timeout(
        _nativeCommandTimeout,
        onTimeout: () {
          // A Dart timeout cannot cancel a native operation. Quarantine this
          // engine so a late acknowledgement cannot overlap a new utterance.
          _nativeUncertain = true;
          final error = TimeoutException('Local speech command timed out.');
          _finish(_playing, error: error);
          throw error;
        },
      );
    });
    late final Future<void> tail;
    tail = next
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() {
      if (identical(_nativeTail, tail)) _nativeTail = null;
    });
    _nativeTail = tail;
    return next;
  }

  Future<void> _stopPlayback({Object? error}) async {
    final playback = _playing;
    playback?.deadline?.cancel();
    _acceptCallbacks = false;
    NeuraFlutterTtsVisemeBridge.reset(_tts);
    Object? failure = error;
    try {
      final result = await _tts?.stop();
      if (result == 0) throw StateError('Local speech stop was rejected.');
    } catch (stopError) {
      _nativeUncertain = true;
      failure = stopError;
      rethrow;
    } finally {
      // Native stop callbacks are untagged. Ignore them during this barrier;
      // resolve only the captured utterance after the acknowledgement.
      _finish(playback, error: failure);
    }
  }

  /// English voices available on this system, for the Settings voice picker.
  Future<List<NeuraVoiceOption>> availableVoices() async {
    if (!await _ensureInit()) return const [];
    if (!playbackAllowed) return const [];

    try {
      final voices = await _tts!.getVoices as List<dynamic>;
      return voices
          .cast<Map<dynamic, dynamic>>()
          .where(
            (voice) =>
                voice['locale']?.toString().toLowerCase().startsWith('en') ??
                false,
          )
          .map(
            (voice) => NeuraVoiceOption(
              name: voice['name'].toString(),
              locale: voice['locale'].toString(),
              gender: voice['gender']?.toString() ?? 'unknown',
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Persists and immediately applies the chosen voice.
  Future<void> setVoice(NeuraVoiceOption voice) async {
    if (!await _ensureInit()) return;
    if (!playbackAllowed) return;

    final result = await _tts!.setVoice({
      'name': voice.name,
      'locale': voice.locale,
    });
    if (result == 0) return;
    _selectedVoiceName = voice.name;
    try {
      final prefs = NeuraPrefsCache.prefs;
      await prefs.setString(_kVoiceNameKey, voice.name);
      await prefs.setString(_kVoiceLocaleKey, voice.locale);
    } catch (_) {
      // Selection still applies for this session even if persistence fails.
    }
  }

  Future<void> setSpeechRate(double value) async {
    _speechRate = value.clamp(0.25, 0.75);
    try {
      await NeuraPrefsCache.prefs.setDouble(_kSpeechRateKey, _speechRate);
    } catch (_) {}
    if (await _ensureInit()) await _tts!.setSpeechRate(_speechRate);
  }

  Future<void> setPitch(double value) async {
    _pitch = value.clamp(0.5, 2.0);
    try {
      await NeuraPrefsCache.prefs.setDouble(_kPitchKey, _pitch);
    } catch (_) {}
    if (await _ensureInit()) await _tts!.setPitch(_pitch);
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    try {
      await NeuraPrefsCache.prefs.setDouble(_kVolumeKey, _volume);
    } catch (_) {}
    if (await _ensureInit()) await _tts!.setVolume(_volume);
  }

  /// Speaks [sampleText] in [voice] without persisting it as the chosen voice.
  Future<void> previewVoice(NeuraVoiceOption voice, String sampleText) async {
    final generation = ++_speechGeneration;
    final cancellation = _cancelGeneration;
    bool current() =>
        generation == _speechGeneration && _configurationAllowed(cancellation);
    if (!await _ensureInit()) return;
    if (!current() || sampleText.trim().isEmpty) return;

    final result = await _tts!.setVoice({
      'name': voice.name,
      'locale': voice.locale,
    });
    if (result == 0) return;
    if (!current()) return;
    await speak(sampleText);
  }

  /// Re-applies the persisted/selected voice after a preview.
  Future<void> restoreSelectedVoice() async {
    if (!await _ensureInit()) return;
    await _applySavedOrDefaultVoice();
  }

  bool _configurationAllowed(int? cancellation) =>
      _engineUsable &&
      (cancellation == null || cancellation == _cancelGeneration);

  Future<void> _applySavedOrDefaultVoice([int? cancellation]) async {
    final tts = _tts;
    if (!_configurationAllowed(cancellation) || tts == null) return;

    try {
      final prefs = NeuraPrefsCache.prefsOrNull;
      final savedName = prefs?.getString(_kVoiceNameKey);
      final savedLocale = prefs?.getString(_kVoiceLocaleKey);
      if (savedName != null && savedLocale != null) {
        if (!_configurationAllowed(cancellation)) return;
        final result = await tts.setVoice({
          'name': savedName,
          'locale': savedLocale,
        });
        if (result != 0) {
          _selectedVoiceName = savedName;
          return;
        }
      }
    } catch (_) {
      // Fall through to the default picker.
    }

    await _selectFemaleVoice(cancellation);
  }

  /// Picks the best available female English voice on this system.
  Future<void> _selectFemaleVoice(int? cancellation) async {
    final tts = _tts;
    if (!_configurationAllowed(cancellation) || tts == null) return;

    try {
      final voices = await tts.getVoices as List<dynamic>;
      final female = voices
          .cast<Map<dynamic, dynamic>>()
          .where(
            (voice) =>
                voice['gender']?.toString().toLowerCase() == 'female' &&
                (voice['locale']?.toString().toLowerCase().startsWith('en') ??
                    false),
          )
          .toList();
      if (female.isEmpty) return;

      final natural = female.firstWhere(
        (voice) =>
            voice['name']?.toString().toLowerCase().contains('natural') ??
            false,
        orElse: () => female.first,
      );
      if (!_configurationAllowed(cancellation)) return;
      final result = await tts.setVoice({
        'name': natural['name'].toString(),
        'locale': natural['locale'].toString(),
      });
      if (result != 0) _selectedVoiceName = natural['name'].toString();
    } catch (_) {
      // Fall back silently to the system default voice.
    }
  }

  /// Waits for completion, cancellation or a bounded failure in Dart.
  /// Startup speech remains disabled until physical Windows acceptance.
  Future<void> speak(String text) {
    if (!playbackAllowed || !enabled || text.trim().isEmpty) {
      return Future<void>.value();
    }
    if (_nativeUncertain) {
      return Future<void>.error(
        StateError('Local speech requires an application restart.'),
      );
    }

    final generation = ++_speechGeneration;
    final playback = _TtsPlayback();
    bool current() =>
        generation == _speechGeneration && _engineUsable && enabled;
    final dispatch = _queueNative(() async {
      if (!current() || !await _ensureInit() || !current()) {
        _finish(playback);
        return;
      }
      await _stopPlayback();
      if (!current()) {
        _finish(playback);
        return;
      }

      final presence = NeuraCompanionPresence.instance.acquireSpeaking();
      if (presence == null) {
        _finish(playback);
        return;
      }
      playback.presence = presence;
      playback.focus = NeuraAudioFocus.instance.acquireSpeech();
      if (!current()) {
        _finish(playback);
        return;
      }
      _playing = playback;
      _acceptCallbacks = true;
      playback.deadline = Timer(_speechTimeout, () {
        if (!identical(_playing, playback)) return;
        ++_speechGeneration;
        ++_cancelGeneration;
        _acceptCallbacks = false;
        NeuraFlutterTtsVisemeBridge.reset(_tts);
        final error = TimeoutException('Local speech completion timed out.');
        final cleanup = _queueNative(() async {
          await _stopPlayback(error: error);
          // Without a terminal callback, a later untagged event could be
          // mistaken for another utterance. Require a restart after timeout.
          _nativeUncertain = true;
        });
        unawaited(
          cleanup.catchError((Object failure, StackTrace stack) {
            _finish(playback, error: failure, stack: stack);
          }),
        );
      });
      final result = await _tts!.speak(text);
      if (result == 0) _finish(playback);
    });
    unawaited(
      dispatch.catchError((Object error, StackTrace stack) {
        _finish(playback, error: error, stack: stack);
      }),
    );
    return playback.done.future;
  }

  /// Invalidates pending speech before waiting for the native stop barrier.
  /// A missing acknowledgement fails within the command deadline and prevents
  /// further speech; it cannot guarantee that a hung native player is silent.
  Future<void> stop() {
    ++_speechGeneration;
    ++_cancelGeneration;
    _acceptCallbacks = false;
    NeuraFlutterTtsVisemeBridge.reset(_tts);
    // A stop before first use must remain a no-op. In particular, do not
    // leave a native command tail owned by a disposed UI/test lifecycle when
    // there has never been a native speech engine to stop.
    if (_tts == null && _initialization == null && _playing == null) {
      return Future<void>.value();
    }
    return _queueNative(_stopPlayback);
  }

  /// The singleton normally lives for the process. Owners of an isolated
  /// service must revoke pending requests and detach its Safe Mode listener.
  Future<void> dispose() {
    if (_disposed) return _disposal ?? Future<void>.value();
    _disposed = true;
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafeModeChanged);
    return _disposal = stop();
  }

  void _onSafeModeChanged() {
    if (!playbackAllowed) {
      unawaited(stop().catchError((_) {}));
    }
  }
}

class _TtsPlayback {
  final done = Completer<void>();
  Timer? deadline;
  NeuraAudioFocusLease? focus;
  NeuraPresenceLease? presence;
}
