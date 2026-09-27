import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/care/screens/neura_care_loop_screen.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/modules/support/guided_support_activity.dart';
import 'package:neuro_companion/modules/support/guided_support_screen.dart';
import 'package:neuro_companion/modules/support/guided_support_store.dart';
import 'package:neuro_companion/modules/support/support_center_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureValues = <String, String>{};
  String? clipboardText;
  late GuidedSupportStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(secureChannel,
        (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          return secureValues[key];
        case 'write':
          secureValues[key] = args['value'] as String;
          return null;
        case 'delete':
          secureValues.remove(key);
          return null;
        case 'containsKey':
          return secureValues.containsKey(key);
      }
      throw StateError('Unexpected secure storage operation: ${call.method}');
    });
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return clipboardText == null
              ? null
              : <String, dynamic>{'text': clipboardText};
        case 'Clipboard.hasStrings':
          return <String, dynamic>{
            'value': clipboardText?.isNotEmpty ?? false,
          };
      }
      return null;
    });
  });

  setUp(() async {
    SafeBoot.instance.safeMode.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await NeuraPrefsCache.prefs.clear();
    clipboardText = null;
    store = GuidedSupportStore();
  });

  tearDown(() {
    SafeBoot.instance.safeMode.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  tearDownAll(() {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('reading an empty preference does not create a key or write anything',
      () async {
    expect(await store.read(), isNull);
    expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
  });

  test(
      'confirmed activity survives reopening, encrypted, with only scoped metadata',
      () async {
    final saved = await store.rememberAfterConfirmation(
        GuidedSupportActivity.grounding,
        stillApproved: () => true);
    final blob =
        NeuraPrefsCache.prefs.getString(GuidedSupportStore.storageKey)!;
    expect(blob, isNot(contains('grounding')));
    final clear = await (await MemoryCrypto.demo()).decryptJson(blob);
    expect(
        clear.keys.toSet(), {'version', 'activity', 'confirmedAtUtc', 'scope'});
    final reopened = await GuidedSupportStore().read();
    expect(reopened!.activity, GuidedSupportActivity.grounding);
    expect(reopened.confirmedAtUtc, saved.confirmedAtUtc);
    expect(jsonDecode(reopened.exportText()), clear);
    await store.rememberAfterConfirmation(GuidedSupportActivity.smallPlan,
        stillApproved: () => true);
    expect((await store.read())!.activity, GuidedSupportActivity.smallPlan);
  });

  test('revoked confirmation never starts a write', () async {
    await expectLater(
        store.rememberAfterConfirmation(GuidedSupportActivity.grounding,
            stillApproved: () => false),
        throwsStateError);
    expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.storageKey),
        isFalse);
  });

  test('forget invalidates an in-flight save and removes existing data',
      () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    store = GuidedSupportStore(loadCrypto: () async {
      entered.complete();
      await gate.future;
      return MemoryCrypto.demo();
    });
    final writing = store.rememberAfterConfirmation(
        GuidedSupportActivity.grounding,
        stillApproved: () => true);
    final rejected = expectLater(writing, throwsStateError);
    await entered.future;
    final forgetting = store.forget();
    gate.complete();
    await rejected;
    await forgetting;
    expect(await store.read(), isNull);
  });

  test('Safe Mode blocks recall and save but still allows verified deletion',
      () async {
    await store.rememberAfterConfirmation(GuidedSupportActivity.grounding,
        stillApproved: () => true);
    SafeBoot.instance.safeMode.value = true;
    expect(await store.read(), isNull);
    await expectLater(
        store.rememberAfterConfirmation(GuidedSupportActivity.smallPlan,
            stillApproved: () => true),
        throwsStateError);
    await store.forget();
    expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.storageKey),
        isFalse);
  });

  test('full data wipe suspends future writes and clears the preference',
      () async {
    await store.rememberAfterConfirmation(GuidedSupportActivity.grounding,
        stillApproved: () => true);
    await store.resetAfterDataWipe();
    expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.storageKey),
        isFalse);
    await expectLater(
        store.rememberAfterConfirmation(GuidedSupportActivity.smallPlan,
            stillApproved: () => true),
        throwsStateError);
    expect(await store.read(), isNull);
    expect(await GuidedSupportStore().read(), isNull);
    expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.storageKey),
        isFalse);
  });

  test('corruption is surfaced, never accepted as unencrypted preference data',
      () async {
    await NeuraPrefsCache.prefs.setString(
        GuidedSupportStore.storageKey,
        RememberedSupportActivity(
                GuidedSupportActivity.grounding, DateTime.now().toUtc())
            .exportText());
    await expectLater(store.read(), throwsA(anything));
    await store.forget();
    expect(await store.read(), isNull);
  });

  test('unavailable encryption cannot fall back to plaintext storage',
      () async {
    store = GuidedSupportStore(
        loadCrypto: () => Future.error(StateError('Unavailable')));
    await expectLater(
        store.rememberAfterConfirmation(GuidedSupportActivity.grounding,
            stillApproved: () => true),
        throwsStateError);
    expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.storageKey),
        isFalse);
  });

  test('unavailable OS credentials surface and still permit deletion',
      () async {
    await store.rememberAfterConfirmation(GuidedSupportActivity.grounding,
        stillApproved: () => true);
    final unavailable = GuidedSupportStore(
        loadCrypto: () =>
            Future.error(StateError('OS credentials unavailable')));
    await expectLater(unavailable.read(), throwsStateError);
    await unavailable.forget();
    expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.storageKey),
        isFalse);
  });

  test('Safe Mode entered during encryption revokes the pending save',
      () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    store = GuidedSupportStore(loadCrypto: () async {
      entered.complete();
      await gate.future;
      return MemoryCrypto.demo();
    });
    final writing = store.rememberAfterConfirmation(
        GuidedSupportActivity.grounding,
        stillApproved: () => true);
    final rejected = expectLater(writing, throwsStateError);
    await entered.future;
    SafeBoot.instance.safeMode.value = true;
    gate.complete();
    await rejected;
    expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.storageKey),
        isFalse);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    store = _ScreenStore();
    await tester
        .pumpWidget(MaterialApp(home: GuidedSupportScreen(store: store)));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(find.text(text), 160,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> checkIn(
      WidgetTester tester, GuidedSupportActivity activity) async {
    await tapText(tester, activity.label);
    for (var i = 1; i < activity.steps.length; i++) {
      await tapText(tester, 'Next step');
    }
    await tapText(tester, 'Check in (optional)');
  }

  testWidgets('Care Loop and Support Center entry points open and exit support',
      (tester) async {
    for (final host in <Widget>[
      const NeuraCareLoopScreen(),
      const SupportCenterScreen(),
    ]) {
      await tester.pumpWidget(MaterialApp(home: host));
      await tester.pumpAndSettle();
      expect(find.text('Help me through this'), findsOneWidget);
      await tester.tap(find.text('Help me through this'));
      await tester.pumpAndSettle();
      expect(find.byType(GuidedSupportScreen), findsOneWidget);
      expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.storageKey),
          isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(GuidedSupportScreen), findsNothing);
    }
  });

  for (final activity in GuidedSupportActivity.values) {
    testWidgets(
        '${activity.label} completes with a skippable check-in and no persistence',
        (tester) async {
      await pumpScreen(tester);
      await checkIn(tester, activity);
      expect(find.text('How was that for you?'), findsOneWidget);
      await tapText(tester, 'Done');
      expect(find.text('What would help right now?'), findsOneWidget);
      expect((store as _ScreenStore).record, isNull);
      expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
    });
  }

  testWidgets(
      'helpful rating and cancelled remember dialog never imply permission',
      (tester) async {
    await pumpScreen(tester);
    await checkIn(tester, GuidedSupportActivity.grounding);
    await tapText(tester, 'Helped a little');
    expect((store as _ScreenStore).record, isNull);
    await tapText(tester, 'Remember what helped…');
    await tapText(tester, 'Not now');
    expect((store as _ScreenStore).record, isNull);
  });

  testWidgets('worse response offers human support without suggesting memory',
      (tester) async {
    await pumpScreen(tester);
    await checkIn(tester, GuidedSupportActivity.grounding);
    await tapText(tester, 'Felt worse');
    expect(find.textContaining("Let's stop this activity"), findsOneWidget);
    expect(find.text('Remember what helped…'), findsNothing);
    await tapText(tester, 'Reach a person');
    expect(find.textContaining('988'), findsOneWidget);
    expect((store as _ScreenStore).record, isNull);
    expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
  });

  testWidgets('drafts clear on switching, backgrounding, and finishing',
      (tester) async {
    await pumpScreen(tester);
    await tapText(tester, 'Quiet writing');
    await tester.enterText(find.byType(TextField), 'Sensitive temporary words');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await tester.enterText(find.byType(TextField), 'Another private thought');
    await tapText(tester, 'Choose another activity');
    await tapText(tester, 'Quiet writing');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await tester.enterText(find.byType(TextField), 'Do not save this');
    await tapText(tester, 'Next step');
    await tapText(tester, 'Check in (optional)');
    expect(find.text('Do not save this'), findsNothing);
    expect((store as _ScreenStore).record, isNull);
    expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
  });

  testWidgets(
      'Safe Mode keeps manual activities available and blocks remembering',
      (tester) async {
    SafeBoot.instance.safeMode.value = true;
    await pumpScreen(tester);
    await checkIn(tester, GuidedSupportActivity.grounding);
    await tapText(tester, 'Helped a little');
    expect(find.text('Remember what helped…'), findsNothing);
    expect((store as _ScreenStore).record, isNull);
    expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
  });

  testWidgets('Safe Mode during the confirmation dialog invalidates consent',
      (tester) async {
    await pumpScreen(tester);
    await checkIn(tester, GuidedSupportActivity.grounding);
    await tapText(tester, 'Helped a little');
    await tapText(tester, 'Remember what helped…');
    SafeBoot.instance.safeMode.value = true;
    await tester.pump();
    await tapText(tester, 'Remember activity');
    expect((store as _ScreenStore).record, isNull);
  });

  testWidgets(
      'explicit consent saves only the activity and it can be forgotten',
      (tester) async {
    await pumpScreen(tester);
    await checkIn(tester, GuidedSupportActivity.grounding);
    await tapText(tester, 'Helped a little');
    await tapText(tester, 'Remember what helped…');
    await tapText(tester, 'Remember activity');
    expect((store as _ScreenStore).record!.activity,
        GuidedSupportActivity.grounding);
    await tapText(tester, 'Done');
    expect(find.textContaining('You asked Neura to remember'), findsOneWidget);
    await tester.tap(find.byTooltip('Remembered activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy preference'));
    await tester.pumpAndSettle();
    final copied = jsonDecode(clipboardText!) as Map<String, dynamic>;
    expect(copied.keys.toSet(),
        {'version', 'activity', 'confirmedAtUtc', 'scope'});
    expect(copied['activity'], 'grounding');
    expect(copied['scope'], 'suggest_in_guided_support');
    expect(copied, isNot(contains('writing')));
    expect(copied, isNot(contains('feedback')));
    await tester.tap(find.byTooltip('Remembered activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget activity'));
    await tester.pumpAndSettle();
    expect((store as _ScreenStore).record, isNull);
    expect(find.textContaining('You asked Neura to remember'), findsNothing);
  });

  testWidgets(
      'unavailable OS credentials stay visible and can still be forgotten',
      (tester) async {
    // Real encryption must finish outside the widget test's fake clock.
    await tester.runAsync(() => store.rememberAfterConfirmation(
        GuidedSupportActivity.grounding,
        stillApproved: () => true));
    expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.storageKey),
        isTrue);
    store = GuidedSupportStore(
        loadCrypto: () =>
            Future.error(StateError('OS credentials unavailable')));
    await tester
        .pumpWidget(MaterialApp(home: GuidedSupportScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be opened'), findsOneWidget);
    await tester.tap(find.byTooltip('Remembered activity'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No activity preference is available'),
        findsOneWidget);
    await tester.tap(find.text('Forget activity'));
    await tester.pumpAndSettle();
    expect(find.text('Remembered activity forgotten.'), findsOneWidget);
    expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.storageKey),
        isFalse);
  });

  testWidgets('backgrounding invalidates an open confirmation after resuming',
      (tester) async {
    await pumpScreen(tester);
    await checkIn(tester, GuidedSupportActivity.grounding);
    await tapText(tester, 'Helped a little');
    await tapText(tester, 'Remember what helped…');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tapText(tester, 'Remember activity');
    expect((store as _ScreenStore).record, isNull);
  });

  testWidgets('dark mode, large text and narrow screens keep support reachable',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      store = _ScreenStore();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
          home: GuidedSupportScreen(store: store)));
      await tester.pumpAndSettle();
      expect(
          Theme.of(tester.element(find.byType(GuidedSupportScreen))).brightness,
          Brightness.dark);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tapText(tester, 'One small plan');
      await tester.scrollUntilVisible(find.byType(TextField), 160,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A small step');
      await tester.scrollUntilVisible(find.text('Finish without check-in'), 160,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Finish without check-in'), findsOneWidget);
      await tapText(tester, 'Next step');
      await tapText(tester, 'Next step');
      await tapText(tester, 'Check in (optional)');
      await tapText(tester, 'Done');
      await tester.scrollUntilVisible(find.text('Reach a person'), 160,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Reach a person'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}

// Widget tests exercise permission UI and lifecycle independently of the real
// encryption/store tests above, without crossing Flutter's fake clock.
class _ScreenStore extends GuidedSupportStore {
  RememberedSupportActivity? record;

  @override
  Future<RememberedSupportActivity?> read() async => record;

  @override
  Future<RememberedSupportActivity> rememberAfterConfirmation(
      GuidedSupportActivity activity,
      {required bool Function() stillApproved}) async {
    if (!stillApproved()) throw StateError('Approval expired.');
    return record = RememberedSupportActivity(activity, DateTime.now().toUtc());
  }

  @override
  Future<void> forget() async {
    record = null;
  }
}
