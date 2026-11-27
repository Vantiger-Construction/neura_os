import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/insights/services/weekly_summarist_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    await NeuraPrefsCache.prefs.clear();
  });

  test('a correction is kept for the next weekly draft', () async {
    final service = WeeklySummaristService.instance;
    expect(service.pendingCorrection, isNull);

    await service.recordCorrection(WeeklyNarrativeCorrection.tooHarsh);
    expect(service.pendingCorrection, WeeklyNarrativeCorrection.tooHarsh);

    await service.recordCorrection(WeeklyNarrativeCorrection.tooLong);
    expect(service.pendingCorrection, WeeklyNarrativeCorrection.tooLong);
  });

  test('every correction carries fixed guidance, never the user’s words', () {
    for (final correction in WeeklyNarrativeCorrection.values) {
      expect(correction.label, isNotEmpty);
      expect(correction.guidance, startsWith('The reader '));
      expect(
        WeeklyNarrativeCorrection.byName(correction.name),
        correction,
      );
    }
    expect(WeeklyNarrativeCorrection.byName('anything else'), isNull);
    expect(WeeklyNarrativeCorrection.byName(null), isNull);
  });
}
