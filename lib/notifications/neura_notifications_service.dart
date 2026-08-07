import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../modules/core/app_log.dart';

/// Opt-in Windows toast notifications for three existing app-open-gated
/// signals ([WeeklySummaristService], [LegacyDeadmanService]) plus a daily
/// mood check-in reminder -- the one genuinely new schedule this adds.
///
/// Confirmed via a throwaway boot-time spike that Windows toasts render on
/// this unpackaged build without MSIX packaging or a Start Menu shortcut
/// (init + show both completed with no exception). Per the plugin's own
/// docs, [cancelAll]/[cancel] on already-*delivered* notifications is a
/// documented no-op without package identity -- this only matters for
/// pulling back a toast already shown, not for stopping future ones, which
/// is handled by gating every call behind the live pref value.
///
/// Daily nudge scheduling deliberately avoids adding a timezone-detection
/// dependency: it converts the desired local wall-clock time to a UTC
/// instant using the platform's own [DateTime.timeZoneOffset] (always
/// correct) rather than looking up the device's IANA timezone name. The
/// tradeoff is the repeat anchor drifts by an hour across a DST transition
/// -- acceptable for a beta reminder feature.
class NeuraNotificationsService {
  NeuraNotificationsService._();
  static final NeuraNotificationsService instance = NeuraNotificationsService._();

  static const _weeklyReviewId = 1001;
  static const _legacyOverdueId = 1002;
  static const _dailyMoodNudgeId = 1003;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _available = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      tz_data.initializeTimeZones();
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          windows: WindowsInitializationSettings(
            appName: 'Neura',
            appUserModelId: 'Neura.NeuraCompanion.Beta',
            guid: 'a1b2c3d4-e5f6-4789-a1b2-c3d4e5f6a7b8',
          ),
        ),
      );
      _available = ok ?? false;
    } catch (e) {
      _available = false;
      await AppLog.instance.warn('neura_notifications_init_failed: $e');
    }
  }

  Future<void> showWeeklyReviewReadyNotification() async {
    if (!await _ready()) return;
    await _showSafely(
      _weeklyReviewId,
      'Your weekly review is ready',
      'Neura put together this week\'s reflection -- take a look when you have a moment.',
    );
  }

  Future<void> showLegacyOverdueNotification() async {
    if (!await _ready()) return;
    await _showSafely(
      _legacyOverdueId,
      'Legacy Guard check-in overdue',
      'It\'s been a while since your last check-in. Open Neura to confirm you\'re okay.',
    );
  }

  Future<void> _showSafely(int id, String title, String body) async {
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(),
      );
    } catch (e) {
      await AppLog.instance.warn('neura_notifications_show_failed: $e');
    }
  }

  Future<void> scheduleDailyMoodNudge(TimeOfDay at) async {
    if (!await _ready()) return;
    try {
      final now = DateTime.now();
      var next = DateTime(now.year, now.month, now.day, at.hour, at.minute);
      if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
      final scheduled = tz.TZDateTime.from(next.toUtc(), tz.UTC);

      await _plugin.zonedSchedule(
        id: _dailyMoodNudgeId,
        title: 'How are you feeling today?',
        body: 'A quick mood check-in with Neura only takes a few seconds.',
        scheduledDate: scheduled,
        notificationDetails: const NotificationDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      await AppLog.instance.warn('neura_notifications_schedule_failed: $e');
    }
  }

  Future<void> cancelDailyMoodNudge() async {
    if (!_available) return;
    try {
      await _plugin.cancel(id: _dailyMoodNudgeId);
    } catch (e) {
      await AppLog.instance.warn('neura_notifications_cancel_failed: $e');
    }
  }

  Future<void> cancelAll() async {
    if (!_available) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      await AppLog.instance.warn('neura_notifications_cancel_all_failed: $e');
    }
  }

  Future<bool> _ready() async {
    if (!_initialized) await init();
    return _available;
  }
}
