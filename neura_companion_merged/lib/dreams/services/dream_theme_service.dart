import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/dream_entry.dart';
import 'dream_service.dart';

class DreamThemeSummary {
  final String topTheme;
  final List<String> topTags;
  final List<String> topWords;

  DreamThemeSummary({required this.topTheme, required this.topTags, required this.topWords});
}

class DreamThemeService {
  DreamThemeService._internal();
  static final DreamThemeService instance = DreamThemeService._internal();

  static const _keyDreams = 'dream_entries_v1';

  List<DreamEntry> _entries = [];
  bool _loaded = false;

  List<DreamEntry> get entries =>
      List.unmodifiable(_entries..sort((a, b) => a.date.compareTo(b.date)));

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyDreams);
    if (raw == null) {
      _entries = [];
      _loaded = true;
      return;
    }
    try {
      final list = json.decode(raw);
      if (list is List) {
        _entries = list
            .whereType<Map<String, dynamic>>()
            .map((m) => DreamEntry.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      } else {
        _entries = [];
      }
    } catch (e) {
      // Self-heal: corrupted JSON -> clear and restart.
      _entries = [];
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyDreams);
    }
    _loaded = true;
  }

  /// Naive keyword-based theme detection to avoid external dependencies.
  List<String> detectThemes(String text) {
    final lower = text.toLowerCase();
    final Set<String> themes = {};

    void addIf(bool cond, String theme) {
      if (cond) themes.add(theme);
    }

    addIf(lower.contains('fall') || lower.contains('falling'), 'falling');
    addIf(lower.contains('fly') || lower.contains('flying'), 'flying');
    addIf(lower.contains('chase') || lower.contains('chased'), 'being_chased');
    addIf(lower.contains('water') || lower.contains('ocean') || lower.contains('sea'),
        'water');
    addIf(lower.contains('school') || lower.contains('class'), 'school');
    addIf(lower.contains('teeth') || lower.contains('tooth'), 'teeth');
    addIf(lower.contains('lost') || lower.contains('cannot find'), 'lost');
    addIf(lower.contains('family') || lower.contains('mom') || lower.contains('dad'),
        'family');
    addIf(lower.contains('work') || lower.contains('job') || lower.contains('boss'),
        'work');
    addIf(lower.contains('house') || lower.contains('home'), 'home');

    if (themes.isEmpty) {
      themes.add('other');
    }
    return themes.toList();
  }

  Future<void> addDream({
    required DateTime date,
    required String text,
  }) async {
    final themes = detectThemes(text);
    final entry = DreamEntry(
      id: DateTime.now().toIso8601String(),
      date: date,
      title: 'Dream',
      description: text,
      themes: themes,
    );
    await DreamService.instance.addOrUpdateDream(entry);
  }

  /// Aggregate recurring themes across recent dreams.
  Future<DreamThemeSummary> computeSummary({required int days}) async {
    final dreams = await DreamService.instance.loadDreams();
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final recent = dreams.where((d) => d.date.isAfter(cutoff)).toList();
    final Map<String, int> counts = {};
    for (final d in recent) {
      for (final t in d.themes) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final top = counts.entries.isEmpty ? null : counts.entries.reduce((a, b) => a.value > b.value ? a : b);
    return DreamThemeSummary(topTheme: top?.key ?? 'unknown', topTags: [], topWords: []);
  }

  Future<Map<String, int>> themeCounts() async {
    final dreams = await DreamService.instance.loadDreams();
    final Map<String, int> counts = {};
    for (final d in dreams) {
      for (final t in d.themes) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts;
  }
}
