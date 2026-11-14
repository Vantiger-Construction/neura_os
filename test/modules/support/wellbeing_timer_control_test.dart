import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/support/wellbeing_session_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

class _TestStopwatch extends Fake implements Stopwatch {
  Duration _elapsed = Duration.zero;
  bool _running = false;

  @override
  int get elapsedMicroseconds => _elapsed.inMicroseconds;
  @override
  bool get isRunning => _running;
  @override
  void start() => _running = true;
  @override
  void stop() => _running = false;
  @override
  void reset() => _elapsed = Duration.zero;

  void advance(Duration duration) {
    if (_running) _elapsed += duration;
  }
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

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(850, 1100);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    if (find.text(label).evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump();
    }
    await tester.scrollUntilVisible(find.text(label), 160,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tester.tap(find.text(label));
    await tester.pump();
  }

  String draft(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  Future<void> advance(
      WidgetTester tester, _TestStopwatch watch, Duration duration) async {
    watch.advance(duration);
    await tester.pump(duration);
  }

  testWidgets('a suggestion preserves custom writing until confirmed',
      (tester) async {
    await pump(tester, const WellbeingSessionScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic personal step');
    await tap(tester, 'Take a rest');
    expect(draft(tester), 'Synthetic personal step');
  });

  testWidgets('a repeated start request cannot reset an active timer',
      (tester) async {
    await pump(tester, const WellbeingSessionScreen());
    final start = tester
        .widget<FilledButton>(find.widgetWithText(
            FilledButton, 'Try a five-minute timer (optional)'))
        .onPressed!;
    await tap(tester, 'Try a five-minute timer (optional)');
    await tester.pump(const Duration(minutes: 2));
    start();
    await tester.pump(const Duration(minutes: 3));
    final completed =
        find.textContaining('Five minutes are up').evaluate().isNotEmpty;
    await tap(tester, 'Stop and clear');
    expect(completed, isTrue);
  });

  testWidgets('pause preserves writing and resumes only the remaining time',
      (tester) async {
    final watch = _TestStopwatch();
    await pump(tester, WellbeingSessionScreen(stopwatchFactory: () => watch));
    await tester.enterText(find.byType(TextField), 'Synthetic small step');
    await tap(tester, 'Try a five-minute timer (optional)');
    await advance(tester, watch, const Duration(minutes: 2));
    expect(find.text('3:00 remaining'), findsOneWidget);
    await tap(tester, 'Pause timer');
    expect(watch.isRunning, isFalse);
    await advance(tester, watch, const Duration(minutes: 30));
    expect(draft(tester), 'Synthetic small step');
    expect(find.text('3:00 remaining'), findsOneWidget);
    expect(find.textContaining('Five minutes are up'), findsNothing);
    await tap(tester, 'Resume timer');
    await advance(tester, watch, const Duration(minutes: 2, seconds: 59));
    expect(find.text('0:01 remaining'), findsOneWidget);
    expect(find.textContaining('Five minutes are up'), findsNothing);
    await advance(tester, watch, const Duration(seconds: 1));
    expect(find.textContaining('Five minutes are up'), findsOneWidget);
    expect(find.text('Resume timer'), findsNothing);
    expect(find.text('Pause timer'), findsNothing);
    expect(draft(tester), 'Synthetic small step');
    expect(watch.isRunning, isFalse);
  });

  testWidgets('repeated pauses and clock changes do not extend the time budget',
      (tester) async {
    final watch = _TestStopwatch();
    var wallTime = DateTime(2026, 11, 13, 12);
    await pump(
        tester,
        WellbeingSessionScreen(
            stopwatchFactory: () => watch, now: () => wallTime));
    await tap(tester, 'Try a five-minute timer (optional)');
    for (var minute = 1; minute <= 2; minute++) {
      await advance(tester, watch, const Duration(minutes: 1));
      await tap(tester, 'Pause timer');
      wallTime = wallTime.add(const Duration(days: 1));
      await advance(tester, watch, const Duration(minutes: 10));
      expect(find.text('${5 - minute}:00 remaining'), findsOneWidget);
      await tap(tester, 'Resume timer');
    }
    await advance(tester, watch, const Duration(minutes: 3));
    expect(find.textContaining('Five minutes are up'), findsOneWidget);
  });

  for (final cancellation in [
    'stop',
    'background',
    'cover',
    'safe mode',
    'recovery'
  ]) {
    testWidgets('$cancellation cancels a paused timer and rejects stale resume',
        (tester) async {
      final watch = _TestStopwatch();
      await pump(tester, WellbeingSessionScreen(stopwatchFactory: () => watch));
      await tester.enterText(find.byType(TextField), 'Synthetic paused draft');
      await tap(tester, 'Try a five-minute timer (optional)');
      await advance(tester, watch, const Duration(minutes: 1));
      await tap(tester, 'Pause timer');
      final resume = tester
          .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Resume timer'))
          .onPressed!;
      switch (cancellation) {
        case 'stop':
          await tap(tester, 'Stop and clear');
        case 'background':
          binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          await tester.pump();
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await tester.pump();
        case 'cover':
          final navigator =
              tester.state<NavigatorState>(find.byType(Navigator));
          navigator.push(MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Synthetic cover'))));
          await tester.pumpAndSettle();
          navigator.pop();
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
      expect(draft(tester), isEmpty);
      expect(find.text('Resume timer'), findsNothing);
      resume();
      await advance(tester, watch, const Duration(minutes: 6));
      expect(find.textContaining('Five minutes are up'), findsNothing);
      expect(watch.isRunning, isFalse);
    });
  }

  testWidgets('suggestions can be declined or explicitly accepted',
      (tester) async {
    await pump(tester, const WellbeingSessionScreen());
    await tap(tester, 'Take a rest');
    expect(draft(tester), 'Take a rest');
    expect(find.text('Use suggestion'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Synthetic chosen step');
    await tap(tester, 'Open the document');
    await tap(tester, 'Keep my step');
    expect(draft(tester), 'Synthetic chosen step');
    await tap(tester, 'Open the document');
    await tap(tester, 'Use suggestion');
    expect(draft(tester), 'Open the document');
  });

  testWidgets(
      'editing revokes an older suggestion even when it is proposed again',
      (tester) async {
    await pump(tester, const WellbeingSessionScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic first step');
    await tap(tester, 'Take a rest');
    final oldChoice = tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Use suggestion'))
        .onPressed!;
    await tester.enterText(find.byType(TextField), 'Synthetic edited step');
    await tester.pump();
    expect(find.text('Use suggestion'), findsNothing);
    await tap(tester, 'Take a rest');
    oldChoice();
    await tester.pump();
    expect(draft(tester), 'Synthetic edited step');
    await tap(tester, 'Use suggestion');
    expect(draft(tester), 'Take a rest');
  });

  testWidgets('leaving revokes a pending suggestion and clears writing',
      (tester) async {
    await pump(tester, const WellbeingSessionScreen());
    await tester.enterText(find.byType(TextField), 'Synthetic private step');
    await tap(tester, 'Take a rest');
    final oldChoice = tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Use suggestion'))
        .onPressed!;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    oldChoice();
    await tester.pump();
    expect(draft(tester), isEmpty);
    expect(find.text('Use suggestion'), findsNothing);
  });

  testWidgets(
      'an initially inactive screen waits for an explicit foreground start',
      (tester) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await pump(tester, const WellbeingSessionScreen());
    FilledButton startButton() => tester.widget<FilledButton>(find
        .widgetWithText(FilledButton, 'Try a five-minute timer (optional)'));
    expect(startButton().onPressed, isNull);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(startButton().onPressed, isNotNull);
    await tester.pump(const Duration(minutes: 6));
    expect(find.textContaining('Five minutes are up'), findsNothing);
  });

  testWidgets('routine reminders keep their existing start and stop controls',
      (tester) async {
    await pump(
        tester,
        WellbeingSessionScreen(
            reminder: true, now: () => DateTime(2026, 11, 13, 12)));
    await tap(tester, 'Start this reminder');
    expect(find.text('Pause timer'), findsNothing);
    expect(find.text('Resume timer'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Start this reminder'))
            .onPressed,
        isNull);
    await tap(tester, 'Stop and clear');
    await tester.pump(const Duration(minutes: 6));
    expect(find.textContaining('A gentle invitation:'), findsNothing);
  });

  testWidgets(
      'pause and resume remain reachable with narrow width and large text',
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
        home: const WellbeingSessionScreen()));
    await tester.pumpAndSettle();
    for (final label in [
      'Try a five-minute timer (optional)',
      'Pause timer',
      'Resume timer',
      'Stop and clear'
    ]) {
      final target = find.text(label);
      for (var attempt = 0;
          target.hitTestable().evaluate().isEmpty && attempt < 15;
          attempt++) {
        await tester.drag(find.byType(ListView), const Offset(0, -160));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(target.hitTestable(), findsOneWidget);
      await tester.tap(target.hitTestable());
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });
}
