import 'package:flutter/foundation.dart';

@immutable
class WeeklySummary {
  final int days;
  final int stormsCount;
  final int safetyStormsCount;
  final int dreamsCount;
  final String topStormFeeling;
  final String topDreamTheme;
  final String vibeSentence;

  const WeeklySummary({
    required this.days,
    required this.stormsCount,
    required this.safetyStormsCount,
    required this.dreamsCount,
    required this.topStormFeeling,
    required this.topDreamTheme,
    required this.vibeSentence,
  });

  const WeeklySummary.empty()
      : days = 7,
        stormsCount = 0,
        safetyStormsCount = 0,
        dreamsCount = 0,
        topStormFeeling = 'unknown',
        topDreamTheme = 'unknown',
        vibeSentence = 'Neura doesn\'t have enough data yet for this week.';
}
