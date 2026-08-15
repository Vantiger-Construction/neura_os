
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/relationship_profile.dart';
import '../services/promise_service.dart';

class RelationshipProfileService {
  RelationshipProfileService._();

  static final RelationshipProfileService instance =
      RelationshipProfileService._();

  static const _storageKey = 'neura_relationship_profiles';
  final _uuid = const Uuid();

  List<RelationshipProfile> _cache = [];

  Future<void> _loadIfNeeded() async {
    if (_cache.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) {
      _cache = [];
      return;
    }
    final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    _cache = list.map(RelationshipProfile.fromJson).toList();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_cache.map((p) => p.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  Future<List<RelationshipProfile>> all() async {
    await _loadIfNeeded();
    return List.unmodifiable(_cache);
  }

  Future<RelationshipProfile> create(String name, {List<String>? tags}) async {
    await _loadIfNeeded();
    final profile = RelationshipProfile(
      id: _uuid.v4(),
      name: name,
      tags: tags ?? [],
    );
    _cache.add(profile);
    await _save();
    return profile;
  }

  Future<void> update(RelationshipProfile profile) async {
    await _loadIfNeeded();
    final idx = _cache.indexWhere((p) => p.id == profile.id);
    if (idx == -1) return;
    _cache[idx] = profile;
    await _save();
  }

  Future<void> touchContact(String profileId,
      {double? moodAfterInteraction}) async {
    await _loadIfNeeded();
    final idx = _cache.indexWhere((p) => p.id == profileId);
    if (idx == -1) return;
    final profile = _cache[idx];
    final now = DateTime.now();
    final newMood = moodAfterInteraction ?? profile.avgMoodAfterInteractions;
    _cache[idx] = profile.copyWith(
      lastContact: now,
      avgMoodAfterInteractions: newMood,
    );
    await _save();
  }

  Future<void> refreshOpenPromiseCounts() async {
    await _loadIfNeeded();
    final promises = await PromiseService.instance.all();
    final byProfile = <String, int>{};
    for (final p in promises) {
      if (p.profileId == null) continue;
      byProfile[p.profileId!] = (byProfile[p.profileId!] ?? 0) + 1;
    }
    _cache = _cache
        .map((profile) => profile.copyWith(
            openPromiseCount: byProfile[profile.id] ?? 0))
        .toList();
    await _save();
  }

  void resetAfterDataWipe() {
    _cache = [];
  }
}
