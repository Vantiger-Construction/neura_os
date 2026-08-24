import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import '../integrations/tts/neura_flutter_tts_viseme_bridge.dart';
import '../reliability/safe_boot.dart';
import '../startup/neura_prefs_cache.dart';

/// One system voice, as surfaced by flutter_tts's getVoices().
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

/// Speaks Neura's chat replies aloud. Wires the existing
/// [NeuraFlutterTtsVisemeBridge] so avatar mouth/viseme events fire on the
/// Neura event bus alongside actual speech.
class NeuraTtsService {
  NeuraTtsService._() {
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }

  static final NeuraTtsService instance = NeuraTtsService._();

  static const _kVoiceNameKey = 'neura.tts.voice_name';
  static const _kVoiceLocaleKey = 'neura.tts.voice_locale';

  FlutterTts? _tts;
  Future<bool>? _initialization;
  bool _initialized = false;
  bool enabled = true;
  String? _selectedVoiceName;
  Completer<void>? _speakCompleter;

  bool get playbackAllowed => !SafeBoot.instance.safeMode.value;

  String? get selectedVoiceName => _selectedVoiceName;

  Future<void> warmUp() async {
    await _ensureInit();
  }

  Future<bool> _ensureInit() {
    if (!playbackAllowed) return Future<bool>.value(false);
    if (_initialized) return Future<bool>.value(true);

    final existing = _initialization;
    if (existing != null) return existing;

    late final Future<bool> operation;
    operation = _initialize().whenComplete(() {
      if (identical(_initialization, operation)) {
        _initialization = null;
      }
    });
    _initialization = operation;
    return operation;
  }

  Future<bool> _initialize() async {
    if (!playbackAllowed) return false;

    final tts = _tts ??= FlutterTts();
    await NeuraFlutterTtsVisemeBridge.attach(
      tts,
      onCompletion: _completeSpeak,
      onCancel: _completeSpeak,
      onError: (_) => _completeSpeak(),
    );

    await tts.setSpeechRate(0.5);
    await tts.setPitch(1.05);
    await _applySavedOrDefaultVoice();

    if (!playbackAllowed) {
      await tts.stop();
      _completeSpeak();
      return false;
    }

    _initialized = true;
    return true;
  }

  void _completeSpeak() {
    final completer = _speakCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

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

  Future<void> setVoice(NeuraVoiceOption voice) async {
    if (!await _ensureInit()) return;
    if (!playbackAllowed) return;

    await _tts!.setVoice({'name': voice.name, 'locale': voice.locale});
    _selectedVoiceName = voice.name;
    try {
      final prefs = NeuraPrefsCache.prefs;
      await prefs.setString(_kVoiceNameKey, voice.name);
      await prefs.setString(_kVoiceLocaleKey, voice.locale);
    } catch (_) {}
  }

  Future<void> previewVoice(NeuraVoiceOption voice, String sampleText) async {
    if (!await _ensureInit()) return;
    if (!playbackAllowed || sampleText.trim().isEmpty) return;

    final tts = _tts!;
    await tts.setVoice({'name': voice.name, 'locale': voice.locale});
    if (!playbackAllowed) return;
    await tts.stop();
    if (!playbackAllowed) return;
    await tts.speak(sampleText);
  }

  Future<void> restoreSelectedVoice() async {
    if (!await _ensureInit()) return;
    await _applySavedOrDefaultVoice();
  }

  Future<void> _applySavedOrDefaultVoice() async {
    final tts = _tts;
    if (!playbackAllowed || tts == null) return;

    try {
      final prefs = NeuraPrefsCache.prefsOrNull;
      final savedName = prefs?.getString(_kVoiceNameKey);
      final savedLocale = prefs?.getString(_kVoiceLocaleKey);
      if (savedName != null && savedLocale != null) {
        if (!playbackAllowed) return;
        await tts.setVoice({'name': savedName, 'locale': savedLocale});
        _selectedVoiceName = savedName;
        return;
      }
    } catch (_) {}

    await _selectFemaleVoice();
  }

  Future<void> _selectFemaleVoice() async {
    final tts = _tts;
    if (!playbackAllowed || tts == null) return;

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
      if (!playbackAllowed) return;
      await tts.setVoice({
        'name': natural['name'].toString(),
        'locale': natural['locale'].toString(),
      });
      _selectedVoiceName = natural['name'].toString();
    } catch (_) {}
  }

  Future<void> speak(String text) async {
    if (!playbackAllowed || !enabled || text.trim().isEmpty) return;
    if (!await _ensureInit()) return;

    final tts = _tts!;
    await tts.stop();
    _completeSpeak();
    if (!playbackAllowed) return;

    final completer = Completer<void>();
    _speakCompleter = completer;
    try {
      final result = await tts.speak(text);
      if (result == 0) _completeSpeak();
      await completer.future;
    } finally {
      if (identical(_speakCompleter, completer)) {
        _speakCompleter = null;
      }
    }
  }

  Future<void> stop() async {
    final tts = _tts;
    if (tts == null) {
      _completeSpeak();
      return;
    }

    try {
      await tts.stop();
    } finally {
      _completeSpeak();
    }
  }

  void _onSafeModeChanged() {
    if (!playbackAllowed) {
      unawaited(stop().catchError((_) {}));
    }
  }
}
