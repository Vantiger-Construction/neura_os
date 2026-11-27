import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/chat/neura_rehearsal_screen.dart';
import 'package:neuro_companion/modules/core/app_log.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_ai_service.dart';
import 'package:neuro_companion/services/neura_generation_cancel.dart';
import 'package:neuro_companion/services/neura_model_router.dart';
import 'package:neuro_companion/services/neura_ollama_chat.dart';
import 'package:neuro_companion/services/neura_rehearsal.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plays the other person with fixed synthetic lines; records each request.
class _ScriptedOllama extends NeuraOllamaChat {
  _ScriptedOllama() : super(supported: true);
  final systems = <String>[];
  final sent = <List<Map<String, dynamic>>>[];

  @override
  Future<String> reply({
    required String system,
    required List<Map<String, dynamic>> messages,
    required NeuraGenerationCancel cancel,
    void Function(String partial)? onPartial,
    List<Map<String, dynamic>> tools = const [],
    String cue = '',
    int? maxTokens,
  }) async {
    systems.add(system);
    sent.add(messages);
    return system.startsWith('You are Neura')
        ? 'You stayed calm and said what you needed.'
        : 'Why is this coming up now?';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    await AppLog.instance.resetAfterDataWipe();
  });

  test('the scenario is bounded and the role keeps safety rules', () {
    final rehearsal = NeuraRehearsal(
      who: '  my   manager ',
      goal: 'Ask for a day off. ' * 40,
      reaction: NeuraRehearsalReaction.upset,
    );
    expect(rehearsal.who, 'my manager');
    expect(
        rehearsal.goal.length, lessThanOrEqualTo(NeuraRehearsal.maxGoalLength));
    final prompt = rehearsal.characterPrompt;
    expect(prompt, contains('Play the other person: my manager'));
    expect(prompt, contains('never cruel'));
    expect(prompt, contains("Let's pause the practice"));
    expect(prompt, contains('hurt or frustrated'));
    expect(() => NeuraRehearsal(who: ' ', goal: 'x'), throwsArgumentError);
    expect(() => NeuraRehearsal(who: 'Sam', goal: ''), throwsArgumentError);
  });

  test('the model sees the user as user and keeps the newest lines', () {
    final rehearsal = NeuraRehearsal(who: 'Sam', goal: 'Talk about chores');
    final lines = [
      const NeuraRehearsalLine(fromUser: false, text: 'Leftover line.'),
      for (var i = 0; i < 40; i++) ...[
        NeuraRehearsalLine(fromUser: true, text: 'Point $i. ' * 10),
        NeuraRehearsalLine(fromUser: false, text: 'Reply $i. ' * 10),
      ],
      const NeuraRehearsalLine(fromUser: true, text: 'Last thing.'),
    ];
    final messages = rehearsal.characterMessages(lines);
    expect(messages.first['role'], 'user');
    expect(messages.last, {'role': 'user', 'content': 'Last thing.'});
    final bytes = messages.fold<int>(0, (n, m) => n + m['content']!.length);
    expect(bytes, lessThanOrEqualTo(NeuraRehearsal.maxTranscriptBytes));
    expect(rehearsal.feedbackPrompt(lines), contains('You: Last thing.'));
  });

  testWidgets('practise offline, then get feedback; nothing else is sent', (
    tester,
  ) async {
    SafeBoot.instance.safeMode.value = false;
    final ollama = _ScriptedOllama();
    final ai = NeuraAiService.forTesting(
      modelRouter: NeuraSecureModelRouter(),
      configuredReader: () => false,
      ollama: ollama,
    );
    await tester.pumpWidget(MaterialApp(
      home: NeuraRehearsalScreen(localOllama: true, aiService: ai),
    ));
    await tester.enterText(find.byKey(const Key('rehearsal-who')), 'Sam');
    await tester.enterText(
      find.byKey(const Key('rehearsal-goal')),
      'I want us to split the chores fairly.',
    );
    await tester.tap(find.byKey(const Key('rehearsal-start')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('rehearsal-message')),
      'Can we talk about the chores?',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Why is this coming up now?'), findsOneWidget);
    expect(ollama.systems.single, contains('Play the other person: Sam'));
    expect(ollama.sent.single, [
      {'role': 'user', 'content': 'Can we talk about the chores?'},
    ]);

    await tester.tap(find.text('How did I do?'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(
      find.text('You stayed calm and said what you needed.'),
      findsOneWidget,
    );
    expect(ollama.systems.last, startsWith('You are Neura'));
    expect(find.text('Practise again'), findsOneWidget);
  });
}
