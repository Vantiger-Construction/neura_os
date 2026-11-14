import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/mood/mood_checkin_screen.dart';
import 'package:neuro_companion/modules/mood/mood_history_screen.dart';
import 'package:neuro_companion/modules/mood/mood_models.dart';
import 'package:neuro_companion/modules/support/guided_support_activity.dart';
import 'package:neuro_companion/modules/support/guided_support_screen.dart';
import 'package:neuro_companion/modules/support/guided_support_store.dart';
import 'package:neuro_companion/modules/support/support_suggestion_choices.dart';
import 'package:neuro_companion/modules/support/human_support_screen.dart';
import 'package:neuro_companion/modules/support/wellbeing_session_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

class _EmptySupportStore extends GuidedSupportStore {
  _EmptySupportStore()
      : super(loadCrypto: () => throw StateError('Unexpected storage access'));

  @override
  Future<RememberedSupportActivity?> read() async => null;

  @override
  Future<SupportSuggestionChoices> readChoices() async =>
      SupportSuggestionChoices();
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
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
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pump();
  }

  String draft(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  for (final entry in <String, Widget Function()>{
    'human support': () => const HumanSupportScreen(),
    'small step': () => const WellbeingSessionScreen(),
    'mood check-in': () =>
        MoodCheckInScreen(save: (_) => throw StateError('Unexpected save')),
    'guided writing': () => GuidedSupportScreen(
        store: _EmptySupportStore(),
        initialActivity: GuidedSupportActivity.quietWriting),
  }.entries) {
    testWidgets('${entry.key} cannot undo or redo cleared private writing',
        (tester) async {
      await pump(tester, entry.value());
      await tester.enterText(find.byType(TextField), 'Synthetic first draft');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(find.byType(TextField), 'Synthetic second draft');
      await tester.pump(const Duration(milliseconds: 600));
      UndoHistoryState<TextEditingValue> history() =>
          tester.state(find.byType(UndoHistory<TextEditingValue>));
      history().undo();
      await tester.pump();
      expect(draft(tester), 'Synthetic first draft');
      history().redo();
      await tester.pump();
      expect(draft(tester), 'Synthetic second draft');

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 600));
      expect(draft(tester), isEmpty);
      history().undo();
      await tester.pump();
      expect(draft(tester), isEmpty);
      history().redo();
      await tester.pump();
      expect(draft(tester), isEmpty);
    });
  }

  testWidgets(
      'a template never overwrites existing writing without confirmation',
      (tester) async {
    await pump(tester, const HumanSupportScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic writing to keep');
    await tap(tester, 'Start a message');
    expect(draft(tester), 'Synthetic writing to keep');
  });

  testWidgets('choosing a support country preserves the message draft',
      (tester) async {
    await pump(tester, const HumanSupportScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic message to keep');
    await tap(tester, 'Canada');
    await tester.pumpAndSettle();
    expect(draft(tester), 'Synthetic message to keep');
    expect(find.text('Call or text 9-8-8'), findsOneWidget);
  });

  testWidgets('initially inactive human support cannot draft or copy',
      (tester) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    String? copied;
    await pump(tester, HumanSupportScreen(copyText: (text) async {
      copied = text;
    }));
    await tap(tester, 'Start a message');
    expect(draft(tester), isEmpty);

    await tester.enterText(find.byType(TextField), 'Synthetic reviewed draft');
    await tap(tester, 'Copy reviewed draft');
    expect(copied, isNull);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(copied, isNull);
    await tap(tester, 'Copy reviewed draft');
    expect(copied, 'Synthetic reviewed draft');
    await tap(tester, 'Clear draft');
    await tap(tester, 'Start a message');
    expect(draft(tester), isNotEmpty);
  });

  for (final exit in ['Escape', 'Back']) {
    testWidgets('$exit disposes human support and revokes pending actions',
        (tester) async {
      await pump(tester, const Scaffold(body: Text('Synthetic home')));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final pendingCopy = Completer<void>();
      final copies = <String>[];
      Widget screen() => HumanSupportScreen(copyText: (text) async {
            copies.add(text);
            await pendingCopy.future;
          });
      unawaited(
          navigator.push(MaterialPageRoute<void>(builder: (_) => screen())));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField), 'Synthetic reviewed draft');
      final oldTemplate = tester
          .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Start a message'))
          .onPressed!;
      final oldCopy = tester
          .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Copy reviewed draft'))
          .onPressed!;
      await tap(tester, 'Copy reviewed draft');
      expect(copies, ['Synthetic reviewed draft']);
      await tester.ensureVisible(find.byType(TextField));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      if (exit == 'Escape') {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.pageBack();
      }
      await tester.pumpAndSettle();
      expect(find.byType(HumanSupportScreen), findsNothing);
      expect(find.text('Synthetic home'), findsOneWidget);
      oldTemplate();
      oldCopy();
      pendingCopy.complete();
      await tester.pump();
      expect(copies, ['Synthetic reviewed draft']);
      expect(tester.takeException(), isNull);

      unawaited(
          navigator.push(MaterialPageRoute<void>(builder: (_) => screen())));
      await tester.pumpAndSettle();
      expect(draft(tester), isEmpty);
      await tester.enterText(find.byType(TextField), 'Synthetic new draft');
      oldTemplate();
      oldCopy();
      await tester.pump();
      expect(draft(tester), 'Synthetic new draft');
      expect(copies, ['Synthetic reviewed draft']);
      expect(
          find.textContaining('Copied to the system clipboard.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('changing the device clock cannot jump the timer countdown',
      (tester) async {
    var now = DateTime(2026, 11, 14, 12);
    await pump(tester, WellbeingSessionScreen(now: () => now));
    await tap(tester, 'Try a five-minute timer (optional)');
    now = now.add(const Duration(hours: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:00 remaining'), findsNothing);
    expect(
        find.textContaining(RegExp(r'^[45]:\d{2} remaining$')), findsOneWidget);
    now = now.subtract(const Duration(hours: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('60:00 remaining'), findsNothing);
    await tap(tester, 'Stop and clear');
  });

  testWidgets('a delayed history read cannot reveal data after backgrounding',
      (tester) async {
    final pending = Completer<List<MoodEntry>>();
    await pump(tester, MoodHistoryScreen(load: () => pending.future));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    pending.complete([
      MoodEntry(
          timestamp: DateTime(2026, 11, 14),
          mood0to10: 5,
          note: 'Synthetic private history')
    ]);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Synthetic private history'), findsNothing);
    expect(find.text('Show saved history'), findsOneWidget);
  });

  testWidgets('replacement can be declined or explicitly accepted',
      (tester) async {
    await pump(tester, const HumanSupportScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic writing to keep');
    await tap(tester, 'Prepare appointment notes');
    expect(draft(tester), 'Synthetic writing to keep');
    await tap(tester, 'Keep my writing');
    expect(draft(tester), 'Synthetic writing to keep');
    expect(find.text('Replace draft'), findsNothing);
    await tap(tester, 'Prepare appointment notes');
    await tap(tester, 'Replace draft');
    expect(draft(tester), startsWith('What I have noticed:'));
    expect(find.text('Replace draft'), findsNothing);
  });

  testWidgets('editing invalidates an outstanding template replacement',
      (tester) async {
    await pump(tester, const HumanSupportScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic original');
    await tap(tester, 'Start a message');
    expect(find.text('Replace draft'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Synthetic newer writing');
    await tester.pump();
    expect(find.text('Replace draft'), findsNothing);
    expect(draft(tester), 'Synthetic newer writing');
  });

  testWidgets('background clears both the draft and pending replacement',
      (tester) async {
    await pump(tester, const HumanSupportScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic original');
    await tap(tester, 'Start a message');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(draft(tester), isEmpty);
    expect(find.text('Replace draft'), findsNothing);
  });

  testWidgets('a late clipboard result does not label newer writing as copied',
      (tester) async {
    final copied = Completer<void>();
    String? clipboardText;
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String;
        await copied.future;
      }
      return null;
    });
    await pump(tester, const HumanSupportScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic reviewed draft');
    await tap(tester, 'Copy reviewed draft');
    await tester.enterText(find.byType(TextField), 'Synthetic edited draft');
    copied.complete();
    await tester.pump();
    expect(clipboardText, 'Synthetic reviewed draft');
    expect(draft(tester), 'Synthetic edited draft');
    expect(
        find.textContaining('Copied to the system clipboard.'), findsNothing);
  });

  testWidgets('history stays hidden until explicitly reopened', (tester) async {
    var reads = 0;
    await pump(tester, MoodHistoryScreen(load: () async {
      reads++;
      return [
        MoodEntry(
            timestamp: DateTime(2026, 11, 14),
            mood0to10: 4,
            note: 'Synthetic saved history')
      ];
    }));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic saved history'), findsOneWidget);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(reads, 1);
    expect(find.text('Synthetic saved history'), findsNothing);
    await tap(tester, 'Show saved history');
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('Synthetic saved history'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide history'));
    await tester.pump();
    expect(reads, 2);
    expect(find.text('Synthetic saved history'), findsNothing);
  });

  testWidgets('covering history revokes a pending read', (tester) async {
    final pending = Completer<List<MoodEntry>>();
    await pump(tester, MoodHistoryScreen(load: () => pending.future));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Cover'))));
    await tester.pumpAndSettle();
    pending.complete([
      MoodEntry(
          timestamp: DateTime(2026, 11, 14),
          mood0to10: 5,
          note: 'Synthetic covered history')
    ]);
    await tester.pump();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Synthetic covered history'), findsNothing);
    expect(find.text('Show saved history'), findsOneWidget);
  });

  testWidgets('restart requirement revokes history and blocks reopening',
      (tester) async {
    var reads = 0;
    final pending = Completer<List<MoodEntry>>();
    await pump(tester, MoodHistoryScreen(load: () {
      reads++;
      return pending.future;
    }));
    SafeBoot.instance.restartRequired.value = true;
    await tester.pump();
    pending.complete([
      MoodEntry(
          timestamp: DateTime(2026, 11, 14),
          mood0to10: 5,
          note: 'Synthetic revoked history')
    ]);
    await tester.pump();
    expect(find.text('Synthetic revoked history'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Show saved history'))
            .onPressed,
        isNull);
    SafeBoot.instance.restartRequired.value = false;
    await tester.pump();
    expect(reads, 1);
    expect(find.text('Synthetic revoked history'), findsNothing);
  });

  testWidgets(
      'inline country selection works with large text on a narrow screen',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: const HumanSupportScreen(urgentOnly: true)));
    await tester.pumpAndSettle();
    Future<void> reveal(Finder target) async {
      for (var attempt = 0;
          target.hitTestable().evaluate().isEmpty && attempt < 12;
          attempt++) {
        await tester.drag(find.byType(ListView), const Offset(0, -180));
        await tester.pumpAndSettle();
      }
      expect(target.hitTestable(), findsOneWidget);
    }

    await reveal(find.text('UK / Ireland'));
    await tester.tap(find.text('UK / Ireland').hitTestable());
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'UK / Ireland'))
            .selected,
        isTrue);
    expect(tester.takeException(), isNull);
    await reveal(find.text('Call 116 123'));
    expect(find.text('Call 116 123'), findsOneWidget);
  });
}
