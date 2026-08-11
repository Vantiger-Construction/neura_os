import 'dart:convert';
import '../models/storm_event.dart';
import '../../shared/services/self_heal_service.dart';
import '../../weekly/services/weekly_snapshot_bridge.dart';
import '../../care/services/care_mode_bridge.dart';
import '../../startup/neura_prefs_cache.dart';

class AfterStormService {
  AfterStormService._internal();
  static final AfterStormService instance = AfterStormService._internal();

  static const _keyEvents = 'after_storm_events_v1';

  final _selfHeal = SelfHealService.instance;
  final _weekly = WeeklySnapshotBridge.instance;
  final _care = CareModeBridge.instance;

  Future<List<StormEvent>> loadEvents() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_keyEvents);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((m) => StormEvent.fromMap(Map<String, dynamic>.from(m)))
          .toList()
        ..sort(
          (a, b) => b.timestamp.compareTo(a.timestamp),
        );
    } catch (e, st) {
      await _selfHeal.recordError('AfterStormService.loadEvents', e, st);
      await prefs.remove(_keyEvents);
      return [];
    }
  }

  Future<void> _saveEvents(List<StormEvent> events) async {
    final prefs = NeuraPrefsCache.prefs;
    final list = events.map((e) => e.toMap()).toList();
    await prefs.setString(_keyEvents, jsonEncode(list));
  }

  Future<void> logEvent(StormEvent event) async {
    final existing = await loadEvents();
    final updated = [event, ...existing];
    await _saveEvents(updated);

    // Fan-out to other systems
    await _weekly.logStormEvent(event);
    await _care.logStormEvent(event);
  }

  Future<StormSummary> computeSummary({int days = 7}) async {
    final events = await loadEvents();
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final recent = events.where((e) => e.timestamp.isAfter(cutoff)).toList();
    if (recent.isEmpty) {
      return const StormSummary.empty();
    }

    final intensityCounts = <String, int>{};
    final feelingCounts = <String, int>{};
    int safetyCount = 0;

    for (final e in recent) {
      intensityCounts[e.intensity] = (intensityCounts[e.intensity] ?? 0) + 1;
      feelingCounts[e.primaryFeeling] =
          (feelingCounts[e.primaryFeeling] ?? 0) + 1;
      if (e.safetyRisk) safetyCount++;
    }

    String topIntensity = 'unknown';
    int topIntensityCount = 0;
    intensityCounts.forEach((k, v) {
      if (v > topIntensityCount) {
        topIntensity = k;
        topIntensityCount = v;
      }
    });

    String topFeeling = 'unknown';
    int topFeelingCount = 0;
    feelingCounts.forEach((k, v) {
      if (v > topFeelingCount) {
        topFeeling = k;
        topFeelingCount = v;
      }
    });

    return StormSummary(
      totalEvents: recent.length,
      days: days,
      mostCommonIntensity: topIntensity,
      mostCommonFeeling: topFeeling,
      safetyRiskEvents: safetyCount,
    );
  }
}

class StormSummary {
  final int totalEvents;
  final int days;
  final String mostCommonIntensity;
  final String mostCommonFeeling;
  final int safetyRiskEvents;

  const StormSummary({
    required this.totalEvents,
    required this.days,
    required this.mostCommonIntensity,
    required this.mostCommonFeeling,
    required this.safetyRiskEvents,
  });

  const StormSummary.empty()
      : totalEvents = 0,
        days = 7,
        mostCommonIntensity = 'unknown',
        mostCommonFeeling = 'unknown',
        safetyRiskEvents = 0;
}
