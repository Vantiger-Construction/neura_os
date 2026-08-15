import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../modules/core/app_log.dart';
import '../reliability/safe_boot.dart';

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
  NeuraNotificationsService._() {
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }
  static final NeuraNotificationsService instance =
      NeuraNotificationsService._();

  static const _weeklyReviewId = 1001;
  static const _legacyOverdueId = 1002;
  static const _dailyMoodNudgeId = 1003;

  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialized = false;
  bool _available = false;
  bool get deliveryAllowed => !SafeBoot.instance.safeMode.value;

  Future<void> init() => _initialize();

  Future<void> _initialize({bool allowInSafeMode = false}) async {
    if (!allowInSafeMode && !deliveryAllowed) return;
    if (_initialized) return;
    _initialized = true;
    try {
      tz_data.initializeTimeZones();
      final plugin = _plugin ??= FlutterLocalNotificationsPlugin();
      final ok = await plugin.initialize(
        settings: const InitializationSettings(
          windows: WindowsInitializationSettings(
            appName: 'Neura',
            appUserModelId: 'Neura.NeuraCompanion.Beta',
            guid: 'a1b2c3d4-e5f6-4789-a1b2-c3d4e5f6a7b8',
          ),
        ),
      );
      _available = ok ?? false;
      if (!allowInSafeMode && !deliveryAllowed && _available) {
        await plugin.cancelAll();
      }
    } catch (e, st) {
      _available = false;
      await AppLog.instance.caught('notifications_init_failed', e, st);
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
    if (!deliveryAllowed) return;
    final plugin = _plugin;
    if (plugin == null) return;
    try {
      await plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(),
      );
    } catch (e, st) {
      await AppLog.instance.caught('notifications_show_failed', e, st);
    }
  }

  Future<void> scheduleDailyMoodNudge(TimeOfDay at) async {
    if (!await _ready()) return;
    try {
      final now = DateTime.now();
      var next = DateTime(now.year, now.month, now.day, at.hour, at.minute);
      if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
      final scheduled = tz.TZDateTime.from(next.toUtc(), tz.UTC);
      if (!deliveryAllowed) return;

      await _plugin!.zonedSchedule(
        id: _dailyMoodNudgeId,
        title: 'How are you feeling today?',
        body: 'A quick mood check-in with Neura only takes a few seconds.',
        scheduledDate: scheduled,
        notificationDetails: const NotificationDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e, st) {
      await AppLog.instance.caught('notifications_schedule_failed', e, st);
    }
  }

  Future<void> cancelDailyMoodNudge() async {
    final plugin = _plugin;
    if (!_available || plugin == null) return;
    try {
      await plugin.cancel(id: _dailyMoodNudgeId);
    } catch (e, st) {
      await AppLog.instance.caught('notifications_cancel_failed', e, st);
    }
  }

  Future<void> cancelAll() async {
    final plugin = _plugin;
    if (!_available || plugin == null) return;
    try {
      await plugin.cancelAll();
    } catch (e, st) {
      await AppLog.instance.caught('notifications_cancel_all_failed', e, st);
    }
  }

  /// Safe Mode may start after a prior normal launch left a repeating OS
  /// reminder behind. Initialize only the cancellation backend, then remove
  /// every Neura schedule; delivery remains blocked by [deliveryAllowed].
  Future<void> cancelAllForSafeMode() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    if (!_initialized || !_available) {
      _initialized = false;
      await _initialize(allowInSafeMode: true);
    }
    if (!_available) {
      throw StateError(
        'The notification platform is unavailable; Safe Mode could not '
        'verify removal of scheduled reminders.',
      );
    }
    await _plugin!.cancelAll();
  }

  /// Wipe-specific cancellation that preserves the normal no-op behavior when
  /// notifications were never scheduled, but lets a platform deletion
  /// failure propagate so the wipe cannot claim full success. Initialization
  /// is attempted even in Safe Mode because a prior launch may have left an
  /// OS-level repeating schedule behind.
  Future<void> cancelAllForDataWipe() async {
    // This build only configures/schedules Windows notifications. Other
    // platforms therefore cannot have a Neura-owned OS schedule to remove.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    if (!_initialized || !_available) {
      _initialized = false;
      await _initialize(allowInSafeMode: true);
    }
    if (!_available) {
      throw StateError(
        'The notification platform is unavailable; scheduled reminders could not be verified as removed.',
      );
    }
    await _plugin!.cancelAll();
  }

  Future<bool> _ready() async {
    if (!deliveryAllowed) return false;
    if (!_initialized) await init();
    return deliveryAllowed && _available;
  }

  void _onSafeModeChanged() {
    if (!deliveryAllowed) unawaited(cancelAll());
  }
}
