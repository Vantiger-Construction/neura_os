import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/after_storm/models/storm_event.dart';
import 'package:neuro_companion/after_storm/services/after_storm_service.dart';
import 'package:neuro_companion/care/services/care_mode_bridge.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:neuro_companion/weekly/services/weekly_snapshot_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('weekly bridge records a storm exactly once without recursion', () async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();

    final event = StormEvent(
      id: 'storm-regression-1',
      timestamp: DateTime.utc(2026, 8, 14, 12),
      intensity: 'medium',
      primaryFeeling: 'overwhelmed',
      shortSummary: 'Regression test event.',
      needNow: 'quiet',
      safetyRisk: false,
    );

    await WeeklySnapshotBridge.instance
        .logStormEvent(event)
        .timeout(const Duration(seconds: 1));

    final stored = await AfterStormService.instance.loadEvents();
    expect(stored, hasLength(1));
    expect(stored.single.id, event.id);

    await CareModeBridge.instance.load();
    expect(CareModeBridge.instance.events, hasLength(1));
    expect(CareModeBridge.instance.events.single.id, event.id);
  });
}
