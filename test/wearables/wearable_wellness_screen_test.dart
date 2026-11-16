import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_companion/constitution/neura_constitution_service.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:neuro_companion/wearables/wearable_gateway.dart';
import 'package:neuro_companion/wearables/wearable_route_observer.dart';
import 'package:neuro_companion/wearables/wearable_snapshot.dart';
import 'package:neuro_companion/wearables/wearable_wellness_screen.dart';

final fixedNow = DateTime.utc(2026, 11, 16, 10);
WearableSnapshot snapshot(Set<WearableMetric> metrics,
        {String status = 'data'}) =>
    WearableSnapshot(
        from: fixedNow.subtract(const Duration(hours: 24)),
        to: fixedNow,
        readings: {
          for (final m in metrics)
            m: WearableReading(
                metric: m,
                status: status,
                value: m == WearableMetric.heartRate ? 72 : 3210,
                at: fixedNow.subtract(const Duration(minutes: 20)),
                start: fixedNow.subtract(const Duration(hours: 10)),
                end: fixedNow.subtract(const Duration(hours: 2)),
                sources: const ['com.example.synthetic'])
        });

class FakeGateway implements WearableGateway {
  int checks = 0;
  int permissionChecks = 0;
  int grants = 0;
  int manages = 0;
  bool supported = true;
  String status = 'data';
  Set<WearableMetric> granted = WearableMetric.values.toSet();
  Set<WearableMetric>? requested;
  final reads = <String, Set<WearableMetric>>{};
  final cancelled = <String>[];
  Completer<WearableSnapshot>? pendingRead;
  Completer<Set<WearableMetric>>? pendingPermissions;
  Completer<void>? pendingGrant;
  @override
  Future<bool> available() async {
    checks++;
    return supported;
  }

  @override
  Future<Set<WearableMetric>> permissions() async {
    permissionChecks++;
    final pending = pendingPermissions;
    if (pending != null) return pending.future;
    return granted;
  }

  @override
  Future<void> requestPermissions(Set<WearableMetric> metrics) async {
    grants++;
    requested = metrics;
    await pendingGrant?.future;
  }

  @override
  Future<WearableSnapshot> read(String id, Set<WearableMetric> metrics) async {
    reads[id] = metrics;
    final pending = pendingRead;
    if (pending != null) return pending.future;
    return snapshot(metrics, status: status);
  }

  @override
  Future<void> cancel(String id) async => cancelled.add(id);
  @override
  Future<bool> managePermissions() async {
    manages++;
    return true;
  }
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  final list = find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;
  if (target.evaluate().isEmpty) {
    tester.state<ScrollableState>(list).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(target, 200,
        scrollable: list, maxScrolls: 60);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await reveal(tester, target);
  final tile = tester.widget<CheckboxListTile>(target);
  tile.onChanged!(!tile.value!);
  await tester.pump();
}

Future<void> open(WidgetTester tester, FakeGateway gateway,
    {Future<void> Function(String)? copy,
    DateTime Function()? now,
    GlobalKey<NavigatorState>? navigator}) async {
  await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: [wearableRouteObserver],
      home: WearableWellnessScreen(
          gateway: gateway,
          now: now ?? () => fixedNow,
          copyText: copy ?? (_) async {})));
  await tester.pumpAndSettle();
}

Future<void> read(WidgetTester tester,
    {Set<WearableMetric> metrics = const {WearableMetric.heartRate}}) async {
  await tap(tester, 'Check connection and permissions');
  for (final m in metrics) {
    await choose(tester, 'read-${m.key}');
  }
  await tap(tester, 'Read selected data (last 24 hours)');
}

Future<void> review(WidgetTester tester) async {
  await choose(tester, 'share-heart_rate');
  await tap(tester, 'Review selected readings for copying');
}

Future<void> approve(WidgetTester tester) =>
    choose(tester, 'approve-wearable-copy');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });
  setUp(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    final service = NeuraConstitutionService.instance;
    await service.save(service.current.copyWith(allowExternalMessages: true));
  });
  tearDown(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
  });

  testWidgets('no automatic permissions or reads; grants never start reading',
      (tester) async {
    final gateway = FakeGateway();
    await open(tester, gateway);
    expect(gateway.checks, 0);
    expect(gateway.permissionChecks, 0);
    expect(gateway.reads, isEmpty);
    for (final tile
        in tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile))) {
      expect(tile.value, isFalse);
    }
    await tap(tester, 'Check connection and permissions');
    await choose(tester, 'read-steps');
    gateway.pendingGrant = Completer<void>();
    await tap(tester, 'Grant selected Android permissions');
    expect(gateway.requested, {WearableMetric.steps});
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    gateway.pendingGrant!.complete();
    await tester.pumpAndSettle();
    expect(gateway.reads, isEmpty);
    await reveal(tester, find.byKey(const ValueKey('read-steps')));
    expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const ValueKey('read-steps')))
            .value,
        isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'only reviewed selection is copied, body note excluded by default',
      (tester) async {
    final gateway = FakeGateway();
    String? copied;
    await open(tester, gateway, copy: (text) async => copied = text);
    await read(tester,
        metrics: {WearableMetric.heartRate, WearableMetric.steps});
    expect(gateway.reads.values.single,
        {WearableMetric.heartRate, WearableMetric.steps});
    await reveal(tester, find.byKey(const ValueKey('share-heart_rate')));
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('share-heart_rate')))
            .value,
        isFalse);
    final note = find.byType(TextField);
    await reveal(tester, note);
    await tester.enterText(note, 'Synthetic private body note');
    await review(tester);
    final preview = tester
        .widget<Text>(find.byKey(const ValueKey('wearable-review-text')))
        .data!;
    expect(find.byType(SelectableText), findsNothing);
    expect(preview, contains('72 bpm'));
    expect(preview, isNot(contains('3210')));
    expect(preview, isNot(contains('private body note')));
    await reveal(tester, find.text('Copy reviewed readings'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Copy reviewed readings'))
            .onPressed,
        isNull);
    await approve(tester);
    await tap(tester, 'Copy reviewed readings');
    expect(copied, preview);
    expect(gateway.permissionChecks, 2);
    await reveal(tester, find.byKey(const ValueKey('approve-wearable-copy')));
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('approve-wearable-copy')))
            .value,
        isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  for (final status in ['no_data', 'permission_required']) {
    testWidgets('$status is explicit and cannot be selected for sharing',
        (tester) async {
      final gateway = FakeGateway()..status = status;
      await open(tester, gateway);
      await read(tester);
      await reveal(
          tester,
          find.textContaining(status == 'no_data'
              ? 'No data supplied for this window; this is not zero.'
              : 'Permission not granted.'));
      expect(find.byKey(const ValueKey('share-heart_rate')), findsNothing);
      await tap(tester, 'Stop and clear');
      expect(find.byKey(const ValueKey('share-heart_rate')), findsNothing);
      expect(find.textContaining('72 bpm'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final interruption in [
    'background',
    'safe mode',
    'recovery',
    'cover and pop',
    'stop',
    'dispose'
  ]) {
    testWidgets('late read is discarded after $interruption; no restart',
        (tester) async {
      final gateway = FakeGateway()
        ..pendingRead = Completer<WearableSnapshot>();
      final navigator = GlobalKey<NavigatorState>();
      await open(tester, gateway, navigator: navigator);
      await read(tester);
      final id = gateway.reads.keys.single;
      switch (interruption) {
        case 'background':
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        case 'safe mode':
          SafeBoot.instance.safeMode.value = true;
          SafeBoot.instance.safeMode.value = false;
        case 'recovery':
          SafeBoot.instance.restartRequired.value = true;
          SafeBoot.instance.restartRequired.value = false;
        case 'cover and pop':
          navigator.currentState!.push(MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Cover'))));
          navigator.currentState!.pop();
        case 'stop':
          await tester.tap(find.byTooltip('Stop and clear readings'));
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
      }
      await tester.pump();
      expect(gateway.cancelled, contains(id));
      gateway.pendingRead!.complete(snapshot({WearableMetric.heartRate}));
      await tester.pumpAndSettle();
      expect(find.textContaining('72 bpm'), findsNothing);
      expect(gateway.reads.length, 1);
      if (interruption != 'dispose') await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('unsupported connector never offers sample data', (tester) async {
    final gateway = FakeGateway()..supported = false;
    await open(tester, gateway);
    await tap(tester, 'Check connection and permissions');
    await choose(tester, 'read-steps');
    await reveal(tester, find.text('Read selected data (last 24 hours)'));
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(
                FilledButton, 'Read selected data (last 24 hours)'))
            .onPressed,
        isNull);
    expect(gateway.reads, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'changed note revokes preview, including captured approval callback',
      (tester) async {
    final gateway = FakeGateway();
    await open(tester, gateway);
    await read(tester);
    await review(tester);
    await reveal(tester, find.byKey(const ValueKey('approve-wearable-copy')));
    final oldApproval = tester
        .widget<CheckboxListTile>(
            find.byKey(const ValueKey('approve-wearable-copy')))
        .onChanged!;
    await approve(tester);
    await reveal(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Synthetic changed note');
    await tap(tester, 'Include my body note');
    await tap(tester, 'Review selected readings for copying');
    oldApproval(true);
    await tester.pump();
    await reveal(tester, find.byKey(const ValueKey('approve-wearable-copy')));
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('approve-wearable-copy')))
            .value,
        isFalse);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('wearable-review-text')))
            .data,
        contains('Synthetic changed note'));
    await tester.pumpWidget(const SizedBox());
  });

  for (final cause in [
    'expiry',
    'clock rollback',
    'policy',
    'permission revocation'
  ]) {
    testWidgets('copy is blocked by $cause', (tester) async {
      final gateway = FakeGateway();
      var clock = fixedNow;
      var copies = 0;
      await open(tester, gateway,
          now: () => clock,
          copy: (_) async {
            copies++;
          });
      await read(tester);
      await review(tester);
      await approve(tester);
      await reveal(tester, find.text('Copy reviewed readings'));
      final callback = tester
          .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Copy reviewed readings'))
          .onPressed!;
      switch (cause) {
        case 'expiry':
          clock = clock.add(const Duration(minutes: 3));
        case 'clock rollback':
          clock = clock.subtract(const Duration(seconds: 1));
        case 'policy':
          final service = NeuraConstitutionService.instance;
          await service
              .save(service.current.copyWith(allowExternalMessages: false));
        case 'permission revocation':
          gateway.granted = {};
      }
      callback();
      await tester.pumpAndSettle();
      expect(copies, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final interruption in ['background', 'safe mode', 'stop', 'dispose']) {
    testWidgets('pending copy permission check cannot outlive $interruption',
        (tester) async {
      final gateway = FakeGateway();
      var copies = 0;
      await open(tester, gateway, copy: (_) async {
        copies++;
      });
      await read(tester);
      await review(tester);
      await approve(tester);
      gateway.pendingPermissions = Completer<Set<WearableMetric>>();
      await tap(tester, 'Copy reviewed readings');
      switch (interruption) {
        case 'background':
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        case 'safe mode':
          SafeBoot.instance.safeMode.value = true;
        case 'stop':
          await tester.tap(find.byTooltip('Stop and clear readings'));
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
      }
      gateway.pendingPermissions!.complete(WearableMetric.values.toSet());
      await tester.pumpAndSettle();
      expect(copies, 0);
      if (interruption != 'dispose') await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'clipboard failure is unconfirmed and never retried automatically',
      (tester) async {
    final gateway = FakeGateway();
    var attempts = 0;
    await open(tester, gateway, copy: (_) async {
      attempts++;
      throw StateError('Synthetic clipboard failure');
    });
    await read(tester);
    await review(tester);
    await approve(tester);
    await tap(tester, 'Copy reviewed readings');
    await reveal(
        tester,
        find.textContaining(
            'Copy or permission confirmation did not complete'));
    expect(attempts, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'safe mode blocks reads while OS permission management stays available',
      (tester) async {
    final gateway = FakeGateway();
    SafeBoot.instance.safeMode.value = true;
    await open(tester, gateway);
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(
                OutlinedButton, 'Check connection and permissions'))
            .onPressed,
        isNull);
    await tap(tester, 'Manage or revoke Android permissions');
    expect(gateway.manages, 1);
    expect(gateway.reads, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
