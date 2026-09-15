import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../modules/core/app_log.dart';
import '../startup/neura_prefs_cache.dart';

class NeuraNotificationsPrefs {
  final bool weeklyReviewReadyEnabled;
  final bool legacyOverdueEnabled;
  final bool dailyMoodNudgeEnabled;
  final int dailyMoodNudgeHour;
  final int dailyMoodNudgeMinute;
  final bool promiseReminderEnabled;

  const NeuraNotificationsPrefs({
    this.weeklyReviewReadyEnabled = false,
    this.legacyOverdueEnabled = false,
    this.dailyMoodNudgeEnabled = false,
    this.dailyMoodNudgeHour = 19,
    this.dailyMoodNudgeMinute = 0,
    this.promiseReminderEnabled = false,
  });

  NeuraNotificationsPrefs copyWith({
    bool? weeklyReviewReadyEnabled,
    bool? legacyOverdueEnabled,
    bool? dailyMoodNudgeEnabled,
    int? dailyMoodNudgeHour,
    int? dailyMoodNudgeMinute,
    bool? promiseReminderEnabled,
  }) {
    return NeuraNotificationsPrefs(
      weeklyReviewReadyEnabled:
          weeklyReviewReadyEnabled ?? this.weeklyReviewReadyEnabled,
      legacyOverdueEnabled: legacyOverdueEnabled ?? this.legacyOverdueEnabled,
      dailyMoodNudgeEnabled:
          dailyMoodNudgeEnabled ?? this.dailyMoodNudgeEnabled,
      dailyMoodNudgeHour: dailyMoodNudgeHour ?? this.dailyMoodNudgeHour,
      dailyMoodNudgeMinute: dailyMoodNudgeMinute ?? this.dailyMoodNudgeMinute,
      promiseReminderEnabled:
          promiseReminderEnabled ?? this.promiseReminderEnabled,
    );
  }

  Map<String, dynamic> toMap() => {
        'weeklyReviewReadyEnabled': weeklyReviewReadyEnabled,
        'legacyOverdueEnabled': legacyOverdueEnabled,
        'dailyMoodNudgeEnabled': dailyMoodNudgeEnabled,
        'dailyMoodNudgeHour': dailyMoodNudgeHour,
        'dailyMoodNudgeMinute': dailyMoodNudgeMinute,
        'promiseReminderEnabled': promiseReminderEnabled,
      };

  static NeuraNotificationsPrefs fromMap(Map<String, dynamic> map) {
    return NeuraNotificationsPrefs(
      weeklyReviewReadyEnabled:
          map['weeklyReviewReadyEnabled'] as bool? ?? false,
      legacyOverdueEnabled: map['legacyOverdueEnabled'] as bool? ?? false,
      dailyMoodNudgeEnabled: map['dailyMoodNudgeEnabled'] as bool? ?? false,
      dailyMoodNudgeHour: (map['dailyMoodNudgeHour'] as num?)?.toInt() ?? 19,
      dailyMoodNudgeMinute: (map['dailyMoodNudgeMinute'] as num?)?.toInt() ?? 0,
      promiseReminderEnabled: map['promiseReminderEnabled'] as bool? ?? false,
    );
  }
}

/// Toggle state for [NeuraNotificationsService], one prefs key holding all
/// three sub-toggles -- same JSON-string-in-prefs pattern as
/// [HumanPrefsController]. Off by default, opt-in.
class NeuraNotificationsPrefsController {
  NeuraNotificationsPrefsController._();
  static final NeuraNotificationsPrefsController instance =
      NeuraNotificationsPrefsController._();

  static const _key = 'neura.notifications.prefs.v1';

  final ValueNotifier<NeuraNotificationsPrefs> prefs =
      ValueNotifier<NeuraNotificationsPrefs>(const NeuraNotificationsPrefs());

  Future<void> init() async {
    try {
      final raw = NeuraPrefsCache.prefs.getString(_key);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        prefs.value =
            NeuraNotificationsPrefs.fromMap(decoded.cast<String, dynamic>());
      }
    } catch (e, st) {
      await AppLog.instance.caught('notifications_prefs_init_failed', e, st);
    }
  }

  Future<void> update(NeuraNotificationsPrefs next) async {
    prefs.value = next;
    try {
      await NeuraPrefsCache.prefs.setString(_key, jsonEncode(next.toMap()));
    } catch (e, st) {
      await AppLog.instance.caught(
        'notifications_prefs_update_failed',
        e,
        st,
      );
    }
  }

  void resetAfterDataWipe() {
    prefs.value = const NeuraNotificationsPrefs();
  }
}
