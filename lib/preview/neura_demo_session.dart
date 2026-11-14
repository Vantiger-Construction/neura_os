import 'package:flutter/foundation.dart';

import '../modules/human/human_prefs.dart';
import '../modules/mood/mood_models.dart';
import '../modules/support/guided_support_activity.dart';
import '../modules/support/guided_support_store.dart';
import '../modules/support/support_suggestion_choices.dart';

/// No persistence, plugin calls, device keys or production-service initialization.
class NeuraDemoSession {
  NeuraDemoSession({DateTime? now}) : now = now ?? DateTime.now() {
    entries.addAll([
      MoodEntry(
          timestamp: this.now.subtract(const Duration(days: 1)),
          mood0to10: 6,
          note: 'Sample: enjoyed a short walk.',
          energy0to10: 5,
          sleepHours: 7),
      MoodEntry(
          timestamp: this.now.subtract(const Duration(days: 2)),
          mood0to10: 4,
          note: 'Sample: chose a quiet break.',
          energy0to10: 3),
    ]);
  }

  final DateTime now;
  final preferences = ValueNotifier(HumanPrefs.defaults);
  final support = DemoSupportStore();
  final List<MoodEntry> entries = [];
  final clipboard = ValueNotifier<String?>(null);
  bool _disposed = false;

  Future<List<MoodEntry>> loadEntries() async =>
      _disposed ? [] : List.of(entries);
  Future<void> addEntry(MoodEntry entry) async {
    if (_disposed) throw StateError('Preview ended');
    if (entries.length >= 30) entries.removeAt(0);
    entries.add(entry);
  }

  Future<void> updatePreferences(HumanPrefs value) async {
    if (!_disposed) preferences.value = value;
  }

  Future<void> copyText(String text) async {
    if (_disposed || text.length > 16000) {
      throw StateError('Preview copy unavailable');
    }
    clipboard.value = text;
  }

  void clearCopy() {
    if (!_disposed) clipboard.value = null;
  }

  void dispose() {
    _disposed = true;
    entries.clear();
    support.close();
    clipboard.value = null;
    clipboard.dispose();
    preferences.dispose();
  }
}

class DemoSupportStore extends GuidedSupportStore {
  DemoSupportStore()
      : super(
            loadCrypto: () =>
                throw StateError('Preview cannot open device storage'));
  RememberedSupportActivity? _record;
  SupportSuggestionChoices _choices = SupportSuggestionChoices();
  bool _closed = false;

  @override
  Future<RememberedSupportActivity?> read() async => _closed ? null : _record;
  @override
  Future<SupportSuggestionChoices> readChoices() async =>
      _closed ? SupportSuggestionChoices() : _choices;
  @override
  Future<RememberedSupportActivity> rememberAfterConfirmation(
      GuidedSupportActivity activity,
      {required bool Function() stillApproved}) async {
    if (_closed || !stillApproved()) {
      throw StateError('Preview approval expired');
    }
    return _record =
        RememberedSupportActivity(activity, DateTime.now().toUtc());
  }

  @override
  Future<void> saveChoicesAfterConfirmation(SupportSuggestionChoices choices,
      {required bool Function() stillApproved}) async {
    if (_closed || !stillApproved()) {
      throw StateError('Preview approval expired');
    }
    _choices = choices;
  }

  @override
  Future<void> forget() async {
    _record = null;
  }

  @override
  Future<void> forgetChoices() async {
    _choices = SupportSuggestionChoices();
  }

  @override
  Future<void> resetAfterDataWipe() async => close();
  void close() {
    _closed = true;
    _record = null;
    _choices = SupportSuggestionChoices();
  }
}
