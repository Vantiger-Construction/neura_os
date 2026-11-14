import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/mood/mood_models.dart';
import 'package:neuro_companion/modules/support/appointment_prep_screen.dart';
import 'package:neuro_companion/modules/support/human_support_screen.dart';
import 'package:neuro_companion/modules/support/usability_feedback_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);
Future<void> tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    final list = find
        .descendant(
            of: find.byType(ListView).first, matching: find.byType(Scrollable))
        .first;
    tester.state<ScrollableState>(list).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(target, 250,
        scrollable: list, maxScrolls: 50);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
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
  });

  testWidgets(
      'appointment reads only on request and exports only a reviewed selection',
      (tester) async {
    var reads = 0;
    String? copied;
    final now = DateTime.utc(2026, 11, 14);
    final entries = [
      MoodEntry(
          timestamp: now.subtract(const Duration(days: 1)),
          mood0to10: 5,
          note: 'Synthetic first secret'),
      MoodEntry(
          timestamp: now.subtract(const Duration(days: 2)),
          mood0to10: 2,
          note: 'Synthetic second secret'),
    ];
    await tester.pumpWidget(MaterialApp(
        home: AppointmentPrepScreen(
            now: () => now,
            load: () async {
              reads++;
              return entries;
            },
            copyText: (text) async {
              copied = text;
            })));
    await tester.pumpAndSettle();
    expect(reads, 0);
    await tester.enterText(
        field('Questions or topics (optional)'), 'Synthetic question');
    await tap(tester, 'Choose saved check-ins (optional)');
    expect(reads, 1);
    final choices = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(choices.every((c) => c.value == false), isTrue);
    choices.first.onChanged!(true);
    await tester.pump();
    await tap(tester, 'Review my summary');
    final preview =
        tester.widget<TextField>(field('Editable summary')).controller!.text;
    expect(preview, contains('mood 5/10'));
    expect(preview, isNot(contains('mood 2/10')));
    expect(preview, isNot(contains('secret')));
    expect(copied, isNull);
    await reveal(tester, find.text('Copy my summary'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Copy my summary'))
            .onPressed,
        isNull);
    await tap(tester, 'I reviewed this summary and choose to copy it');
    await tap(tester, 'Copy my summary');
    expect(copied, preview);
  });

  testWidgets('stale appointment approval cannot authorize a later preview',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: AppointmentPrepScreen(copyText: (_) async {})));
    await tap(tester, 'Review my summary');
    await reveal(
        tester, find.text('I reviewed this summary and choose to copy it'));
    final oldApproval = tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile))
        .onChanged!;
    await tap(tester, 'Stop and clear');
    await tester.enterText(field('Questions or topics (optional)'),
        'Different synthetic question');
    await tap(tester, 'Review my summary');
    oldApproval(true);
    await tester.pump();
    await reveal(tester, find.text('Copy my summary'));
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Copy my summary'))
            .onPressed,
        isNull);
  });

  testWidgets('late appointment load after background cannot reveal records',
      (tester) async {
    final result = Completer<List<MoodEntry>>();
    await tester.pumpWidget(
        MaterialApp(home: AppointmentPrepScreen(load: () => result.future)));
    await tap(tester, 'Choose saved check-ins (optional)');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    result.complete([
      MoodEntry(
          timestamp: DateTime.utc(2026),
          mood0to10: 8,
          note: 'Synthetic hidden note')
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.textContaining('Mood 8/10'), findsNothing);
  });

  for (final form in ['appointment', 'feedback']) {
    for (final interruption in [
      'background',
      'cover',
      'safe mode',
      'recovery',
      'stop'
    ]) {
      testWidgets('$form clears drafts and approval after $interruption',
          (tester) async {
        final appointment = form == 'appointment';
        await tester.pumpWidget(MaterialApp(
            home: appointment
                ? AppointmentPrepScreen(copyText: (_) async {})
                : UsabilityFeedbackScreen(copyText: (_) async {})));
        final label = appointment
            ? 'Questions or topics (optional)'
            : 'What would make the app easier? (optional)';
        await reveal(tester, field(label));
        await tester.enterText(field(label), 'Synthetic private draft');
        await tap(
            tester, appointment ? 'Review my summary' : 'Preview feedback');
        switch (interruption) {
          case 'background':
            binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
            await tester.pump();
            binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          case 'cover':
            final navigator =
                tester.state<NavigatorState>(find.byType(Navigator));
            navigator.push(MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Synthetic cover'))));
            await tester.pumpAndSettle();
            navigator.pop();
          case 'safe mode':
            SafeBoot.instance.safeMode.value = true;
          case 'recovery':
            SafeBoot.instance.restartRequired.value = true;
          case 'stop':
            await tap(tester, 'Stop and clear');
        }
        await tester.pumpAndSettle();
        await reveal(tester, field(label));
        expect(
            tester.widget<TextField>(field(label)).controller!.text, isEmpty);
        expect(
            field(
                appointment ? 'Editable summary' : 'Editable feedback report'),
            findsNothing);
        expect(find.textContaining('Synthetic private draft'), findsNothing);
      });
    }
  }

  testWidgets(
      'feedback is optional and copying requires reviewing the actual report',
      (tester) async {
    String? copied;
    await tester.pumpWidget(
        MaterialApp(home: UsabilityFeedbackScreen(copyText: (text) async {
      copied = text;
    })));
    await tap(tester, 'Preview feedback');
    final preview = tester
        .widget<TextField>(field('Editable feedback report'))
        .controller!
        .text;
    expect(preview, contains('Not tried / skipped'));
    expect(copied, isNull);
    await reveal(tester, find.text('Copy feedback report'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Copy feedback report'))
            .onPressed,
        isNull);
    await tap(tester, 'I reviewed this report and choose to copy it');
    await tester.enterText(
        field('Editable feedback report'), 'Edited synthetic feedback');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Copy feedback report'))
            .onPressed,
        isNull);
    await tap(tester, 'I reviewed this report and choose to copy it');
    await tap(tester, 'Copy feedback report');
    expect(copied, 'Edited synthetic feedback');
  });

  testWidgets(
      'late clipboard completion cannot reveal a cleared feedback report',
      (tester) async {
    final copied = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: UsabilityFeedbackScreen(copyText: (_) => copied.future)));
    await tap(tester, 'Preview feedback');
    await tap(tester, 'I reviewed this report and choose to copy it');
    await tap(tester, 'Copy feedback report');
    await tap(tester, 'Stop and clear');
    copied.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Report copied'), findsNothing);
    expect(field('Editable feedback report'), findsNothing);
  });

  testWidgets('an initially inactive form cannot read or approve data',
      (tester) async {
    var reads = 0;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester
        .pumpWidget(MaterialApp(home: AppointmentPrepScreen(load: () async {
      reads++;
      return [];
    })));
    await tester.pump();
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(
                OutlinedButton, 'Choose saved check-ins (optional)'))
            .onPressed,
        isNull);
    expect(reads, 0);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(reads, 0);
  });

  testWidgets('Escape clears a focused human-support draft and revokes Copy',
      (tester) async {
    var copies = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => HumanSupportScreen(
                                copyText: (_) async => copies++))),
                    child: const Text('Open synthetic route'))))));
    await tap(tester, 'Open synthetic route');
    final draft = field('Your draft (optional)');
    await reveal(tester, draft);
    await tester.enterText(draft, 'Synthetic temporary message');
    await reveal(tester, find.text('Copy reviewed draft'));
    final expiredCopy = tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Copy reviewed draft'))
        .onPressed!;
    await reveal(tester, draft);
    await tester.tap(draft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(HumanSupportScreen), findsNothing);
    expect(find.text('Open synthetic route'), findsOneWidget);
    expiredCopy();
    await tester.pump();
    expect(copies, 0);
    await tap(tester, 'Open synthetic route');
    await reveal(tester, draft);
    expect(tester.widget<TextField>(draft).controller!.text, isEmpty);
  });

  testWidgets('Escape leaves a focused support route', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const AppointmentPrepScreen())),
                    child: const Text('Open synthetic route'))))));
    await tap(tester, 'Open synthetic route');
    await tester.tap(field('Questions or topics (optional)'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Open synthetic route'), findsOneWidget);
  });

  for (final page in [
    const AppointmentPrepScreen(),
    const UsabilityFeedbackScreen()
  ]) {
    testWidgets('${page.runtimeType} supports large text and labeled controls',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: page));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await tap(
            tester,
            page is AppointmentPrepScreen
                ? 'Review my summary'
                : 'Preview feedback');
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip(page is AppointmentPrepScreen
            ? 'Stop and clear appointment notes'
            : 'Stop and clear feedback'));
        await tester.pumpAndSettle();
        expect(
            field(page is AppointmentPrepScreen
                ? 'Editable summary'
                : 'Editable feedback report'),
            findsNothing);
      } finally {
        handle.dispose();
      }
    });
  }
}
