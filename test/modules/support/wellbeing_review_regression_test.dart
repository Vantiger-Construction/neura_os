import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/mood/mood_checkin_screen.dart';
import 'package:neuro_companion/modules/mood/mood_history_screen.dart';
import 'package:neuro_companion/modules/mood/mood_store.dart';
import 'package:neuro_companion/modules/support/human_support_screen.dart';
import 'package:neuro_companion/modules/support/wellbeing_session_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  String? copied;
  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    copied = null;
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
  });
  tearDown(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(850, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(builder: (_) => screen));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pump();
  }

  VoidCallback action(WidgetTester tester, String label) => tester
      .widget<FilledButton>(find.widgetWithText(FilledButton, label))
      .onPressed!;

  String draft(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  Future<void> interrupt(WidgetTester tester, String reason) async {
    switch (reason) {
      case 'background':
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
      case 'cover':
        final nav = tester.state<NavigatorState>(find.byType(Navigator));
        nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
        await tester.pumpAndSettle();
        nav.pop();
        await tester.pumpAndSettle();
      case 'safe mode':
        SafeBoot.instance.safeMode.value = true;
        await tester.pump();
        SafeBoot.instance.safeMode.value = false;
        await tester.pump();
      case 'recovery':
        SafeBoot.instance.restartRequired.value = true;
        await tester.pump();
        SafeBoot.instance.restartRequired.value = false;
        await tester.pump();
    }
  }

  for (final reason in ['background', 'cover', 'safe mode', 'recovery']) {
    testWidgets('$reason revokes an unadmitted Save callback', (tester) async {
      var saves = 0;
      await pump(tester, MoodCheckInScreen(save: (_) async {
        saves++;
      }));
      await tester.enterText(find.byType(TextField), 'Synthetic check-in');
      final oldSave = action(tester, 'Save check-in');
      await interrupt(tester, reason);
      oldSave();
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(draft(tester), isEmpty);
      await tap(tester, 'Save check-in');
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(tester.takeException(), isNull);
    });

    for (final reminder in [false, true]) {
      testWidgets('$reason revokes Start (reminder=$reminder)', (tester) async {
        await pump(
            tester,
            WellbeingSessionScreen(
                reminder: reminder, now: () => DateTime(2026, 11, 14, 12)));
        final label = reminder
            ? 'Start this reminder'
            : 'Try a five-minute timer (optional)';
        final oldStart = action(tester, label);
        await interrupt(tester, reason);
        oldStart();
        await tester.pump(const Duration(minutes: 6));
        expect(find.textContaining('Five minutes are up'), findsNothing);
        expect(find.textContaining('A gentle invitation:'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('Save remains disabled after an unconfirmed platform write',
      (tester) async {
    var attempts = 0;
    await pump(tester, MoodCheckInScreen(save: (_) async {
      attempts++;
      throw const MoodSaveUnconfirmedException();
    }));
    await tester.enterText(find.byType(TextField), 'Synthetic retained note');
    final oldSave = action(tester, 'Save check-in');
    await tap(tester, 'Save check-in');
    expect(draft(tester), 'Synthetic retained note');
    expect(find.textContaining('It may already be stored'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save check-in'))
            .onPressed,
        isNull);
    oldSave();
    await tester.pump();
    expect(attempts, 1);
  });

  testWidgets('unconfirmed history requires restart even after hiding',
      (tester) async {
    var reads = 0;
    await pump(tester, MoodHistoryScreen(load: () async {
      reads++;
      throw const MoodSaveUnconfirmedException();
    }));
    expect(find.textContaining('Restart Neura before opening saved history'),
        findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton && widget.tooltip == 'Refresh history'))
            .onPressed,
        isNull);
    await interrupt(tester, 'background');
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Show saved history'))
            .onPressed,
        isNull);
    expect(reads, 1);
  });

  testWidgets('declining replacement invalidates the old approval callback',
      (tester) async {
    await pump(tester, const HumanSupportScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic writing to keep');
    await tap(tester, 'Start a message');
    final oldApproval = action(tester, 'Replace draft');
    await tap(tester, 'Keep my writing');
    await tap(tester, 'Start a message');
    oldApproval();
    await tester.pump();
    expect(draft(tester), 'Synthetic writing to keep');
    await tap(tester, 'Replace draft');
    expect(draft(tester), isNot('Synthetic writing to keep'));
  });

  for (final reason in ['background', 'cover', 'safe mode', 'recovery']) {
    testWidgets('$reason revokes Copy before newer writing is entered',
        (tester) async {
      await pump(tester, const HumanSupportScreen());
      await tester.enterText(
          find.byType(TextField), 'Synthetic reviewed draft');
      final oldCopy = action(tester, 'Copy reviewed draft');
      await interrupt(tester, reason);
      await tester.enterText(
          find.byType(TextField), 'Synthetic unreviewed draft');
      oldCopy();
      await tester.pump();
      expect(copied, isNull);
      await tap(tester, 'Copy reviewed draft');
      expect(copied, 'Synthetic unreviewed draft');
    });
  }

  testWidgets('an expired template tap cannot refill a cleared screen',
      (tester) async {
    await pump(tester, const HumanSupportScreen());
    final oldTemplate = tester
        .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Start a message'))
        .onPressed!;
    await interrupt(tester, 'background');
    oldTemplate();
    await tester.pump();
    expect(draft(tester), isEmpty);
  });

  testWidgets('initially inactive check-in cannot start a save',
      (tester) async {
    var saves = 0;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await pump(tester, MoodCheckInScreen(save: (_) async {
      saves++;
    }));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save check-in'))
            .onPressed,
        isNull);
    expect(saves, 0);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tap(tester, 'Save check-in');
    await tester.pumpAndSettle();
    expect(saves, 1);
  });

  testWidgets('initially inactive human support cannot copy or apply templates',
      (tester) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await pump(tester, const HumanSupportScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic inactive draft');
    action(tester, 'Copy reviewed draft')();
    await tester.pump();
    await tap(tester, 'Start a message');
    expect(copied, isNull);
    expect(find.text('Replace draft'), findsNothing);
  });
}
