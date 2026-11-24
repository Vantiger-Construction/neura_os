import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../modules/mood/mood_models.dart';
import '../../modules/mood/mood_store.dart';
import '../../profiles/local_profile_service.dart';

/// The gentle weather over Neura's room, from the user's recent mood
/// check-ins. A mirror, never a verdict: it needs a few check-ins, changes
/// slowly with the week, and stays mild when the signal is thin.
enum NeuraMoodWeather {
  /// A warm, clear glow after a good week.
  clear,

  /// The room as it is: no strong trend, or too few check-ins.
  mild,

  /// A soft haze after a low stretch.
  overcast,

  /// Light rain on the glass after a hard week.
  rain;

  /// Check-ins considered.
  static const window = Duration(days: 7);

  /// Fewer check-ins than this in the window leave the room [mild].
  static const minimumEntries = 3;

  /// The weather for [entries] as of [now].
  static NeuraMoodWeather from(List<MoodEntry> entries, DateTime now) {
    final recent = entries
        .where((entry) =>
            !entry.timestamp.isAfter(now) &&
            now.difference(entry.timestamp) <= window)
        .toList();
    if (recent.length < minimumEntries) return mild;
    final average =
        recent.map((entry) => entry.mood0to10).reduce((a, b) => a + b) /
            recent.length;
    if (average >= 7) return clear;
    if (average < 3.5) return rain;
    if (average < 5) return overcast;
    return mild;
  }
}

/// Keeps [weather] current. Reads the encrypted mood history on this device
/// only; profile sessions never read installation-wide mood and get [mild].
class NeuraMoodWeatherService {
  NeuraMoodWeatherService._();

  static final NeuraMoodWeatherService instance = NeuraMoodWeatherService._();

  final ValueNotifier<NeuraMoodWeather> weather =
      ValueNotifier<NeuraMoodWeather>(NeuraMoodWeather.mild);

  Future<void>? _refreshing;

  /// Re-reads recent check-ins. Failures keep the room [mild].
  Future<void> refresh({DateTime? now}) {
    return _refreshing ??=
        _refresh(now ?? DateTime.now()).whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh(DateTime now) async {
    if (LocalProfileService.instance.enabled) {
      weather.value = NeuraMoodWeather.mild;
      return;
    }
    try {
      final entries = await MoodStore.instance.getAll();
      if (LocalProfileService.instance.enabled) {
        weather.value = NeuraMoodWeather.mild;
        return;
      }
      weather.value = NeuraMoodWeather.from(entries, now);
    } catch (_) {
      weather.value = NeuraMoodWeather.mild;
    }
  }

  /// After a local data wipe the room returns to its plain weather.
  void reset() => weather.value = NeuraMoodWeather.mild;
}
