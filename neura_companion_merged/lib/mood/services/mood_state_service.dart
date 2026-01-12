import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/services/self_heal_service.dart';
import '../models/mood_state.dart';

class MoodStateService {
  MoodStateService._internal();
  static final MoodStateService instance = MoodStateService._internal();

  static const _keyMoodState = 'neura_current_mood_state_v1';

  final _selfHeal = SelfHealService.instance;

  MoodState _current = MoodState.neutral();
  MoodState get current => _current;
  String get currentMood => _current.label.name;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyMoodState);
      if (raw != null) {
        final map = Map<String, dynamic>.from(json.decode(raw));
        _current = MoodState.fromMap(map);
      } else {
        _current = MoodState.neutral();
      }
    } catch (e, st) {
      await _selfHeal.recordError('MoodStateService.load', e, st);
      _current = MoodState.neutral();
    }
  }

  Future<void> setMood(String mood) async {
    final label = MoodLabel.values.firstWhere(
      (e) => e.name == mood,
      orElse: () => MoodLabel.neutral,
    );
    _current = _current.copyWith(label: label);
    await _save();
  }

  Future<void> setScore(double score, {String note = ''}) async {
    final label = _labelFromScore(score);
    _current = _current.copyWith(score: score, label: label, note: note);
    await _save();
  }

  MoodLabel _labelFromScore(double score) {
    if (score <= 2.5) return MoodLabel.veryLow;
    if (score <= 4.0) return MoodLabel.low;
    if (score <= 6.0) return MoodLabel.neutral;
    if (score <= 8.0) return MoodLabel.lifted;
    return MoodLabel.high;
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMoodState, json.encode(_current.toMap()));
    } catch (e, st) {
      await _selfHeal.recordError('MoodStateService._save', e, st);
    }
  }
}
