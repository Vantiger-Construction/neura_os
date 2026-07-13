
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/interaction_record.dart';

class InteractionService {
  InteractionService._();

  static final InteractionService instance = InteractionService._();

  static const _storageKey = 'neura_interactions';
  final _uuid = const Uuid();

  List<InteractionRecord> _cache = [];

  Future<void> _loadIfNeeded() async {
    if (_cache.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) {
      _cache = [];
      return;
    }
    final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    _cache = list.map(InteractionRecord.fromJson).toList();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_cache.map((i) => i.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  Future<void> logInteraction({
    required String profileId,
    required InteractionChannel channel,
    required String contextSnippet,
    required int yourMood,
    required int theirMood,
    required String summary,
    String nextStep = '',
  }) async {
    await _loadIfNeeded();
    final record = InteractionRecord(
      id: _uuid.v4(),
      profileId: profileId,
      timestamp: DateTime.now(),
      channel: channel,
      contextSnippet: contextSnippet,
      yourMood: yourMood,
      theirMood: theirMood,
      summary: summary,
      nextStep: nextStep,
    );
    _cache.add(record);
    await _save();
  }

  Future<InteractionRecord?> lastForProfile(String profileId) async {
    await _loadIfNeeded();
    final list = _cache
        .where((i) => i.profileId == profileId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list.isEmpty ? null : list.first;
  }
}
