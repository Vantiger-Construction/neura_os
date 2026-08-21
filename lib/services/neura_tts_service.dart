import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import '../integrations/tts/neura_flutter_tts_viseme_bridge.dart';
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

/// Speaks Neura's chat replies aloud. Wires the existing (previously unused)
/// [NeuraFlutterTtsVisemeBridge] so avatar mouth/viseme events fire on
/// NeuraEventBus alongside actual speech — free lip-sync plumbing for
/// whenever Rive is re-enabled.
class NeuraTtsService {
  NeuraTtsService._();
  static final NeuraTtsService instance = NeuraTtsService._();

  static const _kVoiceNameKey = 'neura.tts.voice_name';
  static const _kVoiceLocaleKey = 'neura.tts.voice_locale';

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool enabled = true;
  String? _selectedVoiceName;
  Completer<void>? _speakCompleter;

  /// The currently active voice's display name, or null before init / if
  /// nothing has been explicitly picked yet (Settings screen uses this to
  /// highlight the active choice).
  String? get selectedVoiceName => _selectedVoiceName;

  /// Forces the native TTS engine to initialize now, without speaking
  /// anything -- see call site in NeuraStartupCoordinator for why.
  Future<void> warmUp() => _ensureInit();

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    // Completion is awaited on the Dart side via [_speakCompleter], not via
    // flutter_tts's native awaitSpeakCompletion(true) -- that native
    // completion-wait path is a documented source of crashes on Windows
    // (github.com/dlutton/flutter_tts#217; the crash tracked in issue #32
    // matches this exact code path: an access violation inside flutter_tts's
    // Windows speak()/coroutine implementation). The completion signal below
    // comes from the same setCompletionHandler callback either way -- this
    // just avoids the native blocking-wait implementation entirely.
    await NeuraFlutterTtsVisemeBridge.attach(
      _tts,
      onCompletion: () => _completeSpeak(),
      onCancel: () => _completeSpeak(),
      onError: (_) => _completeSpeak(),
    );
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.05);
    await _applySavedOrDefaultVoice();
  }

  void _completeSpeak() {
    final completer = _speakCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// English voices available on this system, for the Settings voice picker.
  Future<List<NeuraVoiceOption>> availableVoices() async {
    await _ensureInit();
    try {
      final voices = await _tts.getVoices as List<dynamic>;
      return voices
          .cast<Map<dynamic, dynamic>>()
          .where((v) =>
              v['locale']?.toString().toLowerCase().startsWith('en') ?? false)
          .map((v) => NeuraVoiceOption(
                name: v['name'].toString(),
                locale: v['locale'].toString(),
                gender: v['gender']?.toString() ?? 'unknown',
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Persists and immediately applies the chosen voice.
  Future<void> setVoice(NeuraVoiceOption voice) async {
    await _ensureInit();
    await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
    _selectedVoiceName = voice.name;
    try {
      final prefs = NeuraPrefsCache.prefs;
      await prefs.setString(_kVoiceNameKey, voice.name);
      await prefs.setString(_kVoiceLocaleKey, voice.locale);
    } catch (_) {
      // Selection still applies for this session even if persisting fails.
    }
  }

  /// Speaks [sampleText] in [voice] without persisting it as the chosen
  /// voice — lets the Settings screen let you audition voices before
  /// committing. Call [restoreSelectedVoice] afterwards (e.g. on screen
  /// dispose) so real chat replies go back to using the saved choice.
  Future<void> previewVoice(NeuraVoiceOption voice, String sampleText) async {
    await _ensureInit();
    await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
    await _tts.stop();
    await _tts.speak(sampleText);
  }

  /// Re-applies the persisted/selected voice — used to undo the effect of
  /// [previewVoice] once the user leaves the voice picker without selecting.
  Future<void> restoreSelectedVoice() => _applySavedOrDefaultVoice();

  /// Applies a previously-saved voice choice if there is one, otherwise
  /// falls back to auto-picking a female voice.
  Future<void> _applySavedOrDefaultVoice() async {
    try {
      final prefs = NeuraPrefsCache.prefsOrNull;
      final savedName = prefs?.getString(_kVoiceNameKey);
      final savedLocale = prefs?.getString(_kVoiceLocaleKey);
      if (savedName != null && savedLocale != null) {
        await _tts.setVoice({'name': savedName, 'locale': savedLocale});
        _selectedVoiceName = savedName;
        return;
      }
    } catch (_) {
      // Fall through to the default picker below.
    }
    await _selectFemaleVoice();
  }

  /// Picks the best available female English voice on this system. Windows
  /// only ships "Zira" out of the box (no neural/natural voices installed by
  /// default) — if the user later installs a Windows "Natural" voice (e.g.
  /// Aria) via Settings > Time & language > Speech, this will prefer it,
  /// since natural voices sound far less robotic than the built-in ones.
  Future<void> _selectFemaleVoice() async {
    try {
      final voices = await _tts.getVoices as List<dynamic>;
      final female = voices
          .cast<Map<dynamic, dynamic>>()
          .where((v) =>
              (v['gender']?.toString().toLowerCase() == 'female') &&
              (v['locale']?.toString().toLowerCase().startsWith('en') ?? false))
          .toList();
      if (female.isEmpty) return;

      // Prefer a "Natural"/neural voice by name if one is installed.
      final natural = female.firstWhere(
        (v) => v['name']?.toString().toLowerCase().contains('natural') ?? false,
        orElse: () => female.first,
      );
      await _tts.setVoice({
        'name': natural['name'].toString(),
        'locale': natural['locale'].toString(),
      });
      _selectedVoiceName = natural['name'].toString();
    } catch (_) {
      // Fall back silently to the system default voice.
    }
  }

  /// Speaks [text] and doesn't return until Neura is actually done talking
  /// (or the utterance is cancelled/errors) -- callers, notably the chat
  /// screen's hands-free continuous mode, rely on this so the mic doesn't
  /// restart while she's still audibly speaking and pick up her own voice
  /// through the speakers. Waited for via a Dart-side [Completer] fed by
  /// [NeuraFlutterTtsVisemeBridge]'s completion/cancel/error callbacks,
  /// rather than flutter_tts's native awaitSpeakCompletion(true) -- see the
  /// comment on [_ensureInit] for why.
  Future<void> speak(String text) async {
    if (!enabled || text.trim().isEmpty) return;
    await _ensureInit();
    await _tts.stop();
    final completer = Completer<void>();
    _speakCompleter = completer;
    await _tts.speak(text);
    await completer.future;
  }

  Future<void> stop() async {
    if (!_initialized) return;
    await _tts.stop();
  }
}
