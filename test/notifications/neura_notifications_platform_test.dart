import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/notifications/neura_notifications_prefs.dart';
import 'package:neuro_companion/notifications/neura_notifications_service.dart';
import 'package:neuro_companion/notifications/notifications_settings_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

import '../helpers/data_wipe_fixture.dart';

class _Notifications extends Fake implements FlutterLocalNotificationsPlugin {
  int initializations = 0;
  int shown = 0;
  int cancellations = 0;
  bool failInitialization = false;
  bool failCancellation = false;
  Completer<bool>? initGate;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializations++;
    expect(settings.windows, isNotNull);
    if (failInitialization)
      throw StateError('Synthetic first-use DLL failure.');
    return initGate == null ? true : await initGate!.future;
  }

  @override
  Future<void> show(
      {required int id,
      String? title,
      String? body,
      NotificationDetails? notificationDetails,
      String? payload}) async {
    shown++;
  }

  @override
  Future<void> cancelAll() async {
    cancellations++;
    if (failCancellation) throw StateError('Synthetic cancellation failure.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Notifications plugin;
  late NeuraNotificationsService service;
  late DataWipeFixture fixture;

  setUp(() async {
    fixture = await DataWipeFixture.create();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    NeuraNotificationsPrefsController.instance.resetAfterDataWipe();
    plugin = _Notifications();
    service = NeuraNotificationsService.forTesting(plugin);
  });

  tearDown(() {
    service.dispose();
    debugDefaultTargetPlatformOverride = null;
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    NeuraNotificationsPrefsController.instance.resetAfterDataWipe();
  });

  testWidgets(
      'Android controls explain availability and cannot enable notifications',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester
        .pumpWidget(const MaterialApp(home: NotificationsSettingsScreen()));
    expect(find.text('Notifications are currently available only on Windows.'),
        findsOneWidget);
    final switches =
        tester.widgetList<SwitchListTile>(find.byType(SwitchListTile));
    expect(switches, hasLength(4));
    expect(switches.every((tile) => tile.onChanged == null), isTrue);
    await service.init();
    expect(plugin.initializations, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  test('opt-out is enforced at the service boundary before first native use',
      () async {
    await service.showWeeklyReviewReadyNotification();
    await service.showLegacyOverdueNotification();
    await service.scheduleDailyMoodNudge(const TimeOfDay(hour: 19, minute: 0));
    await service.schedulePromiseReminder(
        promiseId: 'synthetic',
        description: 'Synthetic promise',
        dueAt: DateTime.now().add(const Duration(days: 1)));
    expect(plugin.initializations, 0);
    expect(plugin.shown, 0);
  });

  test(
      'failed first DLL use cannot deliver and a later explicit request may retry',
      () async {
    await fixture.run(() async {
      NeuraNotificationsPrefsController.instance.prefs.value =
          const NeuraNotificationsPrefs(weeklyReviewReadyEnabled: true);
      plugin.failInitialization = true;
      await service.showWeeklyReviewReadyNotification();
      expect(plugin.shown, 0);
      plugin.failInitialization = false;
      await service.showWeeklyReviewReadyNotification();
      expect(plugin.initializations, 2);
      expect(plugin.shown, 1);
      fixture.expectIsolation();
    });
  });

  test('opt-out during first initialization suppresses a late notification',
      () async {
    NeuraNotificationsPrefsController.instance.prefs.value =
        const NeuraNotificationsPrefs(weeklyReviewReadyEnabled: true);
    plugin.initGate = Completer<bool>();
    final showing = service.showWeeklyReviewReadyNotification();
    await Future<void>.delayed(Duration.zero);
    NeuraNotificationsPrefsController.instance.resetAfterDataWipe();
    plugin.initGate!.complete(true);
    await showing;
    expect(plugin.shown, 0);
  });

  test('Safe Mode entry and exit invalidate an in-flight initialization',
      () async {
    NeuraNotificationsPrefsController.instance.prefs.value =
        const NeuraNotificationsPrefs(weeklyReviewReadyEnabled: true);
    plugin.initGate = Completer<bool>();
    final showing = service.showWeeklyReviewReadyNotification();
    await Future<void>.delayed(Duration.zero);
    SafeBoot.instance.safeMode.value = true;
    SafeBoot.instance.safeMode.value = false;
    plugin.initGate!.complete(true);
    await showing;
    expect(plugin.shown, 0);
    expect(plugin.cancellations, greaterThan(0));
  });

  test(
      'restart cancellation initializes only the backend and propagates failure',
      () async {
    SafeBoot.instance.restartRequired.value = true;
    await service.cancelAllForSafeMode();
    expect(plugin.initializations, 1);
    expect(plugin.cancellations, 1);
    expect(service.deliveryAllowed, isFalse);
    plugin.failCancellation = true;
    await expectLater(service.cancelAllForSafeMode(), throwsStateError);
    expect(plugin.shown, 0);
  });
}
