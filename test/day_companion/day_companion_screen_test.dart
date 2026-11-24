import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/day_companion/day_companion_cues.dart';
import 'package:neuro_companion/day_companion/day_companion_screen.dart';
import 'package:neuro_companion/encrypted_memory/companion_memory_service.dart';
import 'package:neuro_companion/neura_shell/neura_shell_state.dart';
import 'package:neuro_companion/neura_shell/widgets/neura_penthouse_scene.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_speech_input.dart';
import 'package:neuro_companion/services/neura_local_speech_input.dart';
import 'package:neuro_companion/teaching/teach_neura_screen.dart';

import '../helpers/companion_memory_fixture.dart';

class _Input implements NeuraSpeechInput {
  final finals = StreamController<String>.broadcast();
  final statuses = StreamController<String>.broadcast();
  final partials = StreamController<String>.broadcast();
  Completer<bool>? opening;
  int starts = 0, stops = 0;
  @override
  bool isListening = false;
  @override
  Stream<String> get finalPhraseStream => finals.stream;
  @override
  Stream<String> get statusStream => statuses.stream;
  @override
  Stream<String> get transcriptStream => partials.stream;
  @override
  Future<bool> startRecording() async {
    starts++;
    isListening = true;
    return opening?.future ?? Future.value(true);
  }

  @override
  Future<String> stopRecording() async {
    stops++;
    isListening = false;
    return '';
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _Input mic;
  late NeuraShellState shell;
  setUp(() {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    shell = NeuraShellState();
    mic = _Input();
  });
  tearDown(() async {
    shell.dispose();
    await mic.finals.close();
    await mic.partials.close();
    await mic.statuses.close();
    SafeBoot.instance.safeMode.value = false;
  });

  Future<void> show(WidgetTester t, {CompanionMemoryService? memory}) async {
    await t.pumpWidget(NeuraShellScope(
        notifier: shell,
        child: MaterialApp(navigatorObservers: [
          teachNeuraRouteObserver
        ], home: DayCompanionScreen(speechInput: mic, memoryService: memory))));
    await t.pumpAndSettle();
    expect(mic.starts, 0);
    await t.tap(find.text('Start listening locally'));
    await t.pump();
  }

  test(
      'selects first-person plans and preferences, filters ordinary speech and credentials',
      () {
    expect(DayCompanionCues.note('I prefer the window seat.'),
        'I prefer the window seat.');
    expect(DayCompanionCues.note('Neura, remember the blue folder.'),
        'the blue folder.');
    for (final s in [
      'She prefers the window seat.',
      'Hello there',
      'I need to change my password.',
      'I need to leave?',
      'I prefer\ninvalid'
    ]) {
      expect(DayCompanionCues.note(s), isNull);
    }
  });

  testWidgets(
      'quiet listening changes the actual painter, supports Undo, and clears private drafts in Safe Mode',
      (t) async {
    await show(t);
    mic.partials.add('I prefer a partial transcript.');
    mic.finals.add('I prefer the window seat.');
    mic.finals.add('I prefer the window seat.');
    await t.pumpAndSettle();
    expect(find.text('Draft notes (1)'), findsOneWidget);
    mic.finals.add("I'm winding down.");
    await t.pumpAndSettle();
    final paint = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is NeuraPenthousePainter);
    final painter =
        t.widget<CustomPaint>(paint).painter as NeuraPenthousePainter;
    expect(painter.lampOn, isFalse);
    expect(painter.curtainsClosed, isTrue);
    await t.tap(find.text('Undo room change'));
    await t.pumpAndSettle();
    expect(shell.penthouse, (lampOn: true, curtainsClosed: false));
    SafeBoot.instance.safeMode.value = true;
    mic.finals.add('I prefer a stale phrase.');
    await t.pumpAndSettle();
    expect(find.text('Draft notes (0)'), findsOneWidget);
    expect(mic.isListening, isFalse);
    final starts = mic.starts;
    SafeBoot.instance.safeMode.value = false;
    await t.pumpAndSettle();
    expect(mic.starts, starts);
  });

  testWidgets(
      'foreground loss cancels pending start and returning focus never resumes',
      (t) async {
    mic.opening = Completer<bool>();
    await show(t);
    expect(mic.starts, 1);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    mic.opening!.complete(true);
    mic.finals.add('I promised to bring the synthetic folder.');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(mic.stops, 1);
    expect(mic.starts, 1);
    expect(find.text('Draft notes (0)'), findsOneWidget);
  });

  testWidgets(
      'covering route immediately stops capture and discards candidates',
      (t) async {
    await show(t);
    mic.finals.add('I plan to sketch tomorrow.');
    await t.pumpAndSettle();
    final nav = t.state<NavigatorState>(find.byType(Navigator));
    unawaited(
        nav.push<void>(MaterialPageRoute(builder: (_) => const Scaffold())));
    nav.pop();
    mic.finals.add('I prefer a late phrase.');
    await t.pumpAndSettle();
    expect(mic.isListening, isFalse);
    expect(find.text('Draft notes (0)'), findsOneWidget);
  });

  testWidgets('reviewed draft can be edited and saved through encrypted memory',
      (t) async {
    late CompanionMemoryFixture f;
    await t.runAsync(() async {
      f = await CompanionMemoryFixture.create();
    });
    await show(t, memory: f.memory);
    mic.finals.add('I promised to bring the synthetic folder.');
    await t.pumpAndSettle();
    expect(mic.starts, greaterThan(0));
    expect(find.text("Draft notes (1)"), findsOneWidget);
    expect(f.crypto.encryptions, 0);
    await t.scrollUntilVisible(find.byType(TextFormField), 160,
        scrollable: find.byType(Scrollable).first);
    await t.enterText(
        find.byType(TextFormField), 'Bring the synthetic sketchbook.');
    final save = find.text('Save note');
    await t.ensureVisible(save);
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await f.disk.run(() async {
        final button = t.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save note'));
        await Function.apply(button.onPressed!, const []);
      });
    });
    await t.pumpAndSettle();
    await t.runAsync(() async {
      final permission = f.grant(CompanionMemoryUse.review);
      final records =
          await f.memory.recall(permission, use: CompanionMemoryUse.review);
      expect(records.single.value, 'Bring the synthetic sketchbook.');
      permission.revoke();
    });
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'home cue proposes the configured action and requires a fresh tap',
      (t) async {
    await t.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await show(t);
    await t.tap(find.text('Real devices · Home Assistant'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Device and action'),
        'Turn on the desk Hue light');
    await t.enterText(find.widgetWithText(TextField, 'Local webhook URL'),
        'http://127.0.0.1:8123/api/webhook/synthetic_test_only_1234');
    await t.tap(find.text('Also for focus'));
    await t.tap(find.text('Add action for this session'));
    await t.pumpAndSettle();
    expect(find.text('Run once'), findsNothing);
    mic.finals.add('I need to focus.');
    await t.pumpAndSettle();
    expect(find.text('Run “Turn on the desk Hue light” on 127.0.0.1:8123?'),
        findsOneWidget);
    expect(find.text('Run once'), findsOneWidget);
    await t.pump(const Duration(minutes: 1));
    expect(find.text('Run once'), findsNothing);
    mic.finals.add('Neura, turn on the desk Hue light.');
    await t.pumpAndSettle();
    expect(find.text('Run once'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Run once'), findsNothing);
    SafeBoot.instance.safeMode.value = true;
    SafeBoot.instance.safeMode.value = false;
    await t.pumpAndSettle();
    expect(find.text('Turn on the desk Hue light'), findsNothing);
    expect(mic.isListening, isFalse);
  });

  testWidgets(
      'ordinary Android silence renews only inside the same foreground session',
      (t) async {
    await show(t);
    mic.statuses.add(NeuraLocalSpeechInput.silenceEnded);
    await t.pump();
    expect(mic.starts, 1);
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(mic.starts, 2);
    mic.statuses.add(NeuraLocalSpeechInput.silenceEnded);
    await t.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump(const Duration(seconds: 2));
    expect(mic.starts, 2);
    expect(mic.isListening, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('Android renews completed phrases and honors a spoken stop',
      (t) async {
    await show(t);
    mic.finals.add('I need to return the synthetic book.');
    await t.pumpAndSettle();
    expect(mic.starts, 2);
    mic.finals.add('Neura, stop listening.');
    await t.pumpAndSettle();
    expect(mic.starts, 2);
    expect(mic.isListening, isFalse);
    expect(find.text('Draft notes (1)'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
