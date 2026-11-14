import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/support/guided_support_activity.dart';
import 'package:neuro_companion/modules/support/guided_support_screen.dart';
import 'package:neuro_companion/modules/support/guided_support_store.dart';
import 'package:neuro_companion/modules/support/support_suggestion_choices.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store extends GuidedSupportStore {
  _Store()
      : super(loadCrypto: () => throw StateError('Unexpected storage access'));

  RememberedSupportActivity? record;
  Future<RememberedSupportActivity?> Function()? load;
  Future<void> Function()? delete;
  int reads = 0;
  int writes = 0;

  @override
  Future<SupportSuggestionChoices> readChoices() async =>
      SupportSuggestionChoices();

  @override
  Future<RememberedSupportActivity?> read() async {
    reads++;
    if (load != null) return load!();
    return record;
  }

  @override
  Future<RememberedSupportActivity> rememberAfterConfirmation(
      GuidedSupportActivity activity,
      {required bool Function() stillApproved}) async {
    if (!stillApproved()) throw StateError('Approval expired');
    writes++;
    return record =
        RememberedSupportActivity(activity, DateTime.utc(2026, 11, 1));
  }

  @override
  Future<void> forget() async {
    if (delete != null) await delete!();
    record = null;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final record = RememberedSupportActivity(
      GuidedSupportActivity.quietWriting, DateTime.utc(2026, 11, 1));
  late _Store store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    await NeuraPrefsCache.prefs.clear();
    store = _Store();
  });

  tearDown(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(WidgetTester tester,
      {GuidedSupportActivity? activity}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(850, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
        home: GuidedSupportScreen(store: store, initialActivity: activity)));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    if (find.text(label).evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(find.text(label), 160,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> management(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Remembered activity'));
    await tester.pumpAndSettle();
  }

  test('restart requirement prevents reading saved support preferences',
      () async {
    var cryptoCalls = 0;
    final realStore = GuidedSupportStore(loadCrypto: () {
      cryptoCalls++;
      throw StateError('Encryption must not be accessed');
    });
    await NeuraPrefsCache.prefs.setString(
        GuidedSupportStore.storageKey, 'synthetic encrypted fixture');
    SafeBoot.instance.restartRequired.value = true;
    expect(await realStore.read(), isNull);
    expect(cryptoCalls, 0);
    expect(NeuraPrefsCache.prefs.getString(GuidedSupportStore.storageKey),
        'synthetic encrypted fixture');
  });

  test('restart requirement rejects new support writes before encryption',
      () async {
    var cryptoCalls = 0;
    final realStore = GuidedSupportStore(loadCrypto: () {
      cryptoCalls++;
      throw StateError('Encryption must not be accessed');
    });
    SafeBoot.instance.restartRequired.value = true;
    await expectLater(
        realStore.rememberAfterConfirmation(GuidedSupportActivity.grounding,
            stillApproved: () => true),
        throwsStateError);
    expect(cryptoCalls, 0);
    expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
  });

  testWidgets('recovery leaves manual activities available without recall',
      (tester) async {
    SafeBoot.instance.restartRequired.value = true;
    store.record = record;
    await pump(tester, activity: GuidedSupportActivity.quietWriting);
    expect(store.reads, 0);
    expect(find.byType(TextField), findsOneWidget);
    await tap(tester, 'Next step');
    await tap(tester, 'Check in (optional)');
    await tap(tester, 'Helped a little');
    expect(find.text('Remember what helped\u2026'), findsNothing);
    expect(store.writes, 0);
  });

  testWidgets('backgrounding redacts an open preference dialog',
      (tester) async {
    store.record = record;
    await pump(tester);
    await management(tester);
    expect(find.textContaining('Quiet writing helped.'), findsOneWidget);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.textContaining('Quiet writing helped.'), findsNothing);
    expect(find.text('Copy preference'), findsNothing);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('Quiet writing helped.'), findsNothing);
    expect(find.text('Request expired'), findsOneWidget);
  });

  testWidgets('restart requirement revokes an open remember request',
      (tester) async {
    await pump(tester);
    await tap(tester, 'Quiet writing');
    await tap(tester, 'Next step');
    await tap(tester, 'Check in (optional)');
    await tap(tester, 'Helped a little');
    expect(
        tester
            .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, 'Helped a little'))
            .selected,
        isTrue);
    expect(SafeBoot.instance.safeMode.value, isFalse);
    await tap(tester, 'Remember what helped\u2026');
    SafeBoot.instance.restartRequired.value = true;
    await tester.pump();
    expect(find.text('Remember activity'), findsNothing);
    expect(find.text('Request expired'), findsOneWidget);
    SafeBoot.instance.restartRequired.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Remember activity'), findsNothing);
    expect(store.writes, 0);
    await tap(tester, 'Close');
    await tap(tester, 'Helped a little');
    await tap(tester, 'Remember what helped\u2026');
    await tester.tap(find.text('Remember activity'));
    await tester.pump();
    expect(find.text('Request expired'), findsNothing);
    await tester.pumpAndSettle();
    expect(store.writes, 1);
    await tap(tester, 'Done');
    expect(find.textContaining('You asked Neura to remember'), findsOneWidget);
    expect(find.text('Show remembered activity'), findsNothing);
  });

  testWidgets('covering guided writing clears its draft and undo history',
      (tester) async {
    await pump(tester, activity: GuidedSupportActivity.quietWriting);
    await tester.enterText(find.byType(TextField), 'Synthetic private draft');
    await tester.pump(const Duration(milliseconds: 600));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Synthetic cover'))));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    tester
        .state<UndoHistoryState<TextEditingValue>>(
            find.byType(UndoHistory<TextEditingValue>))
        .undo();
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
  });

  testWidgets('covering the screen revokes a pending preference read',
      (tester) async {
    final pending = Completer<RememberedSupportActivity?>();
    store.load = () => pending.future;
    await pump(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Synthetic cover'))));
    await tester.pumpAndSettle();
    pending.complete(record);
    await tester.pump();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.textContaining('You asked Neura to remember'), findsNothing);
  });

  testWidgets('late clipboard completion cannot restore a success notice',
      (tester) async {
    final copied = Completer<void>();
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') await copied.future;
      return null;
    });
    store.record = record;
    await pump(tester);
    await management(tester);
    await tester.tap(find.text('Copy preference'));
    await tester.pumpAndSettle();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    copied.complete();
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Preference copied to your clipboard.'), findsNothing);
  });

  test('forgetting remains available during recovery', () async {
    await NeuraPrefsCache.prefs.setString(
        GuidedSupportStore.storageKey, 'synthetic encrypted fixture');
    SafeBoot.instance.safeMode.value = true;
    SafeBoot.instance.restartRequired.value = true;
    final realStore = GuidedSupportStore(
        loadCrypto: () => throw StateError('Unexpected encryption access'));
    await realStore.forget();
    expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.storageKey),
        isFalse);
  });

  testWidgets('an initially inactive screen does not recall a preference',
      (tester) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    store.record = record;
    await pump(tester);
    expect(store.reads, 0);
    SafeBoot.instance.safeMode.value = true;
    SafeBoot.instance.safeMode.value = false;
    await tester.pump();
    expect(store.reads, 0);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(store.reads, 0);
    await tap(tester, 'Show remembered activity');
    expect(store.reads, 1);
    expect(find.textContaining('You asked Neura to remember'), findsOneWidget);
  });

  testWidgets('returning requires an explicit choice to show a preference',
      (tester) async {
    store.record = record;
    await pump(tester);
    expect(store.reads, 1);
    expect(find.textContaining('You asked Neura to remember'), findsOneWidget);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(store.reads, 1);
    expect(find.textContaining('You asked Neura to remember'), findsNothing);
    await tap(tester, 'Show remembered activity');
    expect(store.reads, 2);
    expect(find.textContaining('You asked Neura to remember'), findsOneWidget);
  });

  testWidgets('covering an owned dialog expires it and clears writing',
      (tester) async {
    store.record = record;
    await pump(tester, activity: GuidedSupportActivity.quietWriting);
    await tester.enterText(find.byType(TextField), 'Synthetic covered draft');
    await management(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Synthetic cover'))));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Request expired'), findsOneWidget);
    expect(find.textContaining('Quiet writing helped.'), findsNothing);
    expect(find.text('Copy preference'), findsNothing);
    await tap(tester, 'Close');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(store.writes, 0);
  });

  testWidgets('disposing the owner while its dialog is open is safe',
      (tester) async {
    store.record = record;
    await pump(tester);
    await management(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(store.writes, 0);
  });

  testWidgets('a late deletion failure cannot revive an expired notice',
      (tester) async {
    final deletion = Completer<void>();
    store.record = record;
    store.delete = () => deletion.future;
    await pump(tester);
    await management(tester);
    await tester.tap(find.text('Forget activity'));
    await tester.pumpAndSettle();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    deletion.completeError(StateError('Synthetic deletion failure'));
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not verify deletion'), findsNothing);
    expect(find.text('Remembered activity forgotten.'), findsNothing);
    expect(store.record, same(record));
  });

  testWidgets(
      'finishing after an interruption does not reveal hidden preferences',
      (tester) async {
    store.record = record;
    await pump(tester, activity: GuidedSupportActivity.quietWriting);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tap(tester, 'Finish without check-in');
    expect(store.reads, 1);
    expect(find.textContaining('You asked Neura to remember'), findsNothing);
    await tap(tester, 'Show remembered activity');
    expect(store.reads, 2);
    expect(find.textContaining('You asked Neura to remember'), findsOneWidget);
  });
}
