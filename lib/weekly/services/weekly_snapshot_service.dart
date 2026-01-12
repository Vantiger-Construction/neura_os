import '../../after_storm/services/after_storm_service.dart';
import '../../after_storm/models/storm_event.dart';
import '../../dreams/services/dream_service.dart';
import '../../dreams/services/dream_theme_service.dart';
import '../models/weekly_summary.dart';

class WeeklySnapshotService {
  WeeklySnapshotService._internal();
  static final WeeklySnapshotService instance =
      WeeklySnapshotService._internal();

  final _afterStorm = AfterStormService.instance;
  final _dreams = DreamService.instance;
  final _dreamThemes = DreamThemeService.instance;

  Future<WeeklySummary> buildSummary({int days = 7}) async {
    final storms = await _afterStorm.loadEvents();
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final recentStorms =
        storms.where((e) => e.timestamp.isAfter(cutoff)).toList();

    final dreamThemeSummary =
        await _dreamThemes.computeSummary(days: days);
    final dreams = await _dreams.loadDreams();
    final recentDreams =
        dreams.where((d) => d.date.isAfter(cutoff)).toList();

    if (recentStorms.isEmpty && recentDreams.isEmpty) {
      return const WeeklySummary.empty();
    }

    final feelingCounts = <String, int>{};
    int safetyStorms = 0;
    for (final s in recentStorms) {
      final feeling = s.primaryFeeling.toLowerCase();
      if (feeling.isNotEmpty) {
        feelingCounts[feeling] = (feelingCounts[feeling] ?? 0) + 1;
      }
      if (s.safetyRisk) safetyStorms++;
    }

    String topFeeling = 'unknown';
    int topFeelingCount = 0;
    feelingCounts.forEach((f, c) {
      if (c > topFeelingCount) {
        topFeeling = f;
        topFeelingCount = c;
      }
    });

    final topDreamTheme = (dreamThemeSummary.topTags.isNotEmpty
            ? dreamThemeSummary.topTags.first
            : (dreamThemeSummary.topWords.isNotEmpty
                ? dreamThemeSummary.topWords.first
                : 'unknown'))
        .toString();

    final vibe = _generateVibe(
      storms: recentStorms,
      safetyStorms: safetyStorms,
      dreamsCount: recentDreams.length,
      topFeeling: topFeeling,
      topDreamTheme: topDreamTheme,
    );

    return WeeklySummary(
      days: days,
      stormsCount: recentStorms.length,
      safetyStormsCount: safetyStorms,
      dreamsCount: recentDreams.length,
      topStormFeeling: topFeeling,
      topDreamTheme: topDreamTheme,
      vibeSentence: vibe,
    );
  }

  String _generateVibe({
    required List<StormEvent> storms,
    required int safetyStorms,
    required int dreamsCount,
    required String topFeeling,
    required String topDreamTheme,
  }) {
    if (storms.isEmpty && dreamsCount > 0) {
      return 'Quiet on the outside, busy in your dreams. Neura sees a calm week with inner stories unfolding.';
    }
    if (storms.length >= 5 && safetyStorms == 0) {
      return 'Stormy but resilient: lots of emotional weather, but you kept yourself safe through all of it.';
    }
    if (storms.length >= 3 && safetyStorms > 0) {
      return 'It's been an intense stretch. Neura suggests extra softness and reaching out to trusted people when you can.';
    }
    if (storms.length <= 2 && dreamsCount <= 2) {
      return 'Relatively gentle week. Small waves, small dreams, still worth celebrating that stability.';
    }
    if (topFeeling == 'overwhelmed') {
      return 'Your week had a lot of "too much" energy. Tiny, doable steps will be kinder than big overhauls right now.';
    }
    if (topDreamTheme != 'unknown') {
      return 'A repeating theme around "$topDreamTheme" is showing up. Your brain might be trying to process something important there.';
    }
    return 'Mixed weather, mixed dreams. Neura sees a very human week with ups, downs, and a lot of effort from you.';
  }
}
