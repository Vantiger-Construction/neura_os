import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/human/human_media_query.dart';
import 'package:neuro_companion/modules/human/human_prefs.dart';
import 'package:neuro_companion/modules/support/human_support_screen.dart';
import 'package:neuro_companion/modules/support/wellbeing_home_card.dart';
import 'package:neuro_companion/preview/neura_demo_app.dart';
import 'package:neuro_companion/preview/neura_demo_bootstrap.dart';
import 'package:neuro_companion/preview/neura_demo_session.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:neuro_companion/theme/app_theme.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
  tearDown(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

  testWidgets(
      'unverified and failed native isolation never open the demo or production app',
      (tester) async {
    for (final verifier in <Future<bool> Function()>[
      () async => false,
      () async => throw StateError('Synthetic failure')
    ]) {
      await tester.pumpWidget(
          NeuraDemoBootstrap(key: UniqueKey(), verifyIsolation: verifier));
      await tester.pumpAndSettle();
      expect(find.byType(NeuraDemoApp), findsNothing);
      expect(find.textContaining('Preview unavailable'), findsOneWidget);
      expect(() => NeuraPrefsCache.prefs, throwsStateError);
    }
  });
  testWidgets('a timed-out attestation cannot later open the app',
      (tester) async {
    final gate = Completer<bool>();
    await tester
        .pumpWidget(NeuraDemoBootstrap(verifyIsolation: () => gate.future));
    await tester.pump(const Duration(seconds: 4));
    gate.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(NeuraDemoApp), findsNothing);
  });
  testWidgets(
      'every demo destination stays in memory and personal destinations remain unavailable',
      (tester) async {
    final session = NeuraDemoSession(now: DateTime.utc(2026, 11, 14));
    addTearDown(session.dispose);
    var privateCalls = 0;
    const secure =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(secure, (_) async {
      privateCalls++;
      throw StateError('Private storage forbidden');
    });
    addTearDown(() =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(secure, null));
    await tester.pumpWidget(NeuraDemoApp(session: session));
    await tester.pumpAndSettle();
    final home =
        tester.widget<WellbeingHomeCard>(find.byType(WellbeingHomeCard));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    for (final destination in WellbeingDestination.values) {
      navigator.push(MaterialPageRoute<void>(
          builder: (_) => home.destinationBuilder!(destination)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: destination.name);
      if (destination == WellbeingDestination.journal) {
        expect(find.textContaining('No private record has been opened'),
            findsOneWidget);
      }
      if (destination == WellbeingDestination.reachSomeone) {
        final contacts = find.text('Open my trusted contacts');
        await tester.scrollUntilVisible(contacts, 250,
            scrollable: find
                .descendant(
                    of: find.byType(ListView).last,
                    matching: find.byType(Scrollable))
                .first);
        await tester.tap(contacts);
        await tester.pumpAndSettle();
        expect(find.textContaining('No private record has been opened'),
            findsOneWidget);
        navigator.pop();
        await tester.pumpAndSettle();
      }
      navigator.pop();
      await tester.pumpAndSettle();
    }
    expect(privateCalls, 0);
    expect(() => NeuraPrefsCache.prefs, throwsStateError);
    expect(find.byType(HumanSupportScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('guided handoff keeps clipboard and contacts inside the demo',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(850, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final session = NeuraDemoSession();
    addTearDown(session.dispose);
    var systemCopies = 0;
    var privateCalls = 0;
    const secure =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(secure, (_) async {
      privateCalls++;
      throw StateError('Private storage forbidden');
    });
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') systemCopies++;
      return null;
    });
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(secure, null);
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    Future<void> tapLabel(String label) async {
      final target = find.text(label);
      if (target.evaluate().isEmpty) {
        await tester.scrollUntilVisible(target, 200,
            scrollable: find.byType(Scrollable).first, maxScrolls: 30);
      }
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(NeuraDemoApp(session: session));
    await tester.pumpAndSettle();
    final home =
        tester.widget<WellbeingHomeCard>(find.byType(WellbeingHomeCard));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) =>
            home.destinationBuilder!(WellbeingDestination.quietWriting))));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), 'Synthetic private reflection');
    await tapLabel('Reach a person');
    expect(find.byType(HumanSupportScreen), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await tester.enterText(
        find.byType(TextField), 'Synthetic reviewed message');
    await tapLabel('Copy reviewed draft');
    expect(session.clipboard.value, 'Synthetic reviewed message');
    expect(systemCopies, 0);
    await tapLabel('Open my trusted contacts');
    expect(find.textContaining('No private record has been opened'),
        findsOneWidget);
    expect(privateCalls, 0);
    expect(() => NeuraPrefsCache.prefs, throwsStateError);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('demo copy and check-ins cannot survive disposal', () async {
    final session = NeuraDemoSession();
    await session.copyText('Synthetic clipboard');
    expect(session.clipboard.value, 'Synthetic clipboard');
    session.dispose();
    expect(await session.loadEntries(), isEmpty);
    await expectLater(session.copyText('Late write'), throwsStateError);
  });
  testWidgets('system high contrast selects the actual high contrast theme',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final session = NeuraDemoSession();
    await tester.pumpWidget(NeuraDemoApp(session: session));
    await tester.pumpAndSettle();
    expect(
        Theme.of(tester.element(find.byType(WellbeingHomeCard)))
            .colorScheme
            .outline,
        AppTheme.light(highContrast: true).colorScheme.outline);
    expect(() => NeuraPrefsCache.prefs, throwsStateError);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });
  test(
      'comfort controls preserve system choices and support larger explicit text',
      () {
    final prefs = HumanPrefs.fromJson(
        {...HumanPrefs.defaults.toJson(), 'textScale': 2.0});
    expect(prefs.textScale, 2.0);
    final data = applyHumanAccessibilityPreferences(
        const MediaQueryData(disableAnimations: true, highContrast: true),
        prefs);
    expect(data.disableAnimations, isTrue);
    expect(data.highContrast, isTrue);
    expect(data.textScaler.scale(16), 32);
    expect(
        applyHumanAccessibilityPreferences(const MediaQueryData(),
                HumanPrefs.defaults.copyWith(lowStim: true))
            .disableAnimations,
        isTrue);
    expect(
        HumanPrefs.fromJson(
                {...HumanPrefs.defaults.toJson(), 'textScale': double.nan})
            .textScale,
        1.0);
  });
}
