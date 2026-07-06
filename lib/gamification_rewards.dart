import 'dart:convert';
/// A reward/badge earned through consistent use.
import 'startup/neura_prefs_cache.dart';

class NeuraReward {
  final String id;
  final String title;
  final String description;
  final DateTime earnedAt;

  const NeuraReward({
    required this.id,
    required this.title,
    required this.description,
    required this.earnedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'earnedAt': earnedAt.toIso8601String(),
      };

  factory NeuraReward.fromJson(Map<String, dynamic> m) => NeuraReward(
        id: m['id'] as String? ?? '',
        title: m['title'] as String? ?? '',
        description: m['description'] as String? ?? '',
        earnedAt:
            DateTime.tryParse(m['earnedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Stores and evaluates badge/reward milestones.
class GamificationRewardsService {
  GamificationRewardsService._();
  static final instance = GamificationRewardsService._();

  static const _key = 'neura_rewards_v1';
  List<NeuraReward> _rewards = [];

  List<NeuraReward> get rewards => List.unmodifiable(_rewards);

  Future<void> load() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      _rewards = list
          .whereType<Map<String, dynamic>>()
          .map(NeuraReward.fromJson)
          .toList();
    } catch (_) {
      _rewards = [];
    }
  }

  Future<void> _save() async {
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setString(
        _key, jsonEncode(_rewards.map((r) => r.toJson()).toList()));
  }

  bool hasEarned(String rewardId) => _rewards.any((r) => r.id == rewardId);

  Future<NeuraReward?> grant(
      String id, String title, String description) async {
    if (hasEarned(id)) return null;
    final reward = NeuraReward(
        id: id,
        title: title,
        description: description,
        earnedAt: DateTime.now());
    _rewards.add(reward);
    await _save();
    return reward;
  }
}
