import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/models/journal_entry.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/screens/journal_prompt_screen.dart';
import 'package:neuro_companion/screens/voice_journal_screen.dart';
import 'package:neuro_companion/services/journal_prompt_service.dart';
import 'package:neuro_companion/services/local_journal_store.dart';
import 'package:neuro_companion/services/voice_journal_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    SafeBoot.instance.safeMode.value = false;
    await NeuraPrefsCache.prefs.clear();
  });

  tearDown(() {
    SafeBoot.instance.safeMode.value = false;
  });

  testWidgets(
    'prompt save failure keeps the draft under nonlinear large text',
    (tester) async {
      final store = _FailingJournalStore();
      await tester.pumpWidget(
        _largeTextApp(
          JournalPromptScreen(
            promptService: _FixedPromptService('What mattered today?'),
            journalStore: store,
            now: () => DateTime(2026, 10, 11, 20),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('What mattered today?'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'A careful thought.');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save response'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save response'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not save. Your draft is still here.',
            skipOffstage: false),
        findsOneWidget,
      );
      expect(
          find.text('A careful thought.', skipOffstage: false), findsOneWidget);
      expect(store.writeAttempts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved prompt response reopens with original prompt after time changes',
    (tester) async {
      final store = LocalJournalStore(
        now: () => DateTime.utc(2026, 10, 11, 9),
      );
      var now = DateTime(2026, 10, 11, 9);

      await tester.pumpWidget(
        _largeTextApp(
          JournalPromptScreen(
            promptService: _TimePromptService(),
            journalStore: store,
            now: () => now,
            entryIdFactory: (_) => 'journal_prompt_user_a',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Morning prompt'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Morning response.');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save response'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save response'));
      await tester.pumpAndSettle();

      now = DateTime(2026, 10, 11, 21);
      await tester.pumpWidget(_largeTextApp(const SizedBox.shrink()));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _largeTextApp(
          JournalPromptScreen(
            promptService: _TimePromptService(),
            journalStore: store,
            now: () => now,
            entryIdFactory: (_) => 'journal_prompt_user_a_new',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Morning prompt'), findsOneWidget);
      expect(find.text('Evening prompt'), findsNothing);
      expect(find.text('Morning response.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Updated response.');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save response'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save response'));
      await tester.pumpAndSettle();

      final saved = await store.findById('journal_prompt_user_a');
      expect(saved, isNotNull);
      expect(saved!.content, contains('Morning prompt'));
      expect(saved.content, isNot(contains('Evening prompt')));
      expect(saved.content, contains('Updated response.'));
    },
  );

  testWidgets(
    'legacy prompt response with empty moodTag reopens and migrates on save',
    (tester) async {
      final store = LocalJournalStore(
        now: () => DateTime.utc(2026, 10, 11, 9),
      );
      await store.upsertEntry(
        id: 'journal_prompt_2026-10-11',
        timestamp: DateTime(2026, 10, 11, 9),
        content: 'Prompt:\nLegacy prompt\n\nResponse:\nLegacy response.',
      );

      await tester.pumpWidget(
        _largeTextApp(
          JournalPromptScreen(
            promptService: _FixedPromptService('New prompt'),
            journalStore: store,
            now: () => DateTime(2026, 10, 11, 21),
            entryIdFactory: (_) => 'journal_prompt_new_uuid',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Legacy prompt'), findsOneWidget);
      expect(find.text('New prompt'), findsNothing);
      expect(find.text('Legacy response.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Migrated response.');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save response'));
      await tester.pumpAndSettle();

      final saved = await store.findById('journal_prompt_2026-10-11');
      expect(saved, isNotNull);
      expect(saved!.moodTag, 'journal_prompt:2026-10-11');
      expect(saved.content, contains('Legacy prompt'));
      expect(saved.content, contains('Migrated response.'));
      expect(await store.findById('journal_prompt_new_uuid'), isNull);
    },
  );

  testWidgets(
    'prompt history can reopen a prior-day saved response',
    (tester) async {
      final store = LocalJournalStore(
        now: () => DateTime.utc(2026, 10, 11, 9),
      );
      await store.upsertEntry(
        id: 'journal_prompt_2026-10-10',
        timestamp: DateTime(2026, 10, 10, 9),
        content: 'Prompt:\nPrior prompt\n\nResponse:\nPrior response.',
      );

      await tester.pumpWidget(
        _largeTextApp(
          JournalPromptScreen(
            promptService: _FixedPromptService('Today prompt'),
            journalStore: store,
            now: () => DateTime(2026, 10, 11, 9),
            entryIdFactory: (_) => 'journal_prompt_today',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final priorPromptButton = find.ancestor(
        of: find.textContaining('Prior prompt'),
        matching: find.byType(OutlinedButton),
      );
      await tester.scrollUntilVisible(
        priorPromptButton,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
      await tester.pumpAndSettle();
      await tester.tap(priorPromptButton);
      await tester.pumpAndSettle();

      expect(find.text('Prior prompt', skipOffstage: false), findsOneWidget);
      expect(find.text('Prior response.', skipOffstage: false), findsOneWidget);
    },
  );

  testWidgets('prompt history show-all reaches older saved responses',
      (tester) async {
    final store = LocalJournalStore(
      now: () => DateTime.utc(2026, 10, 20, 9),
    );
    for (var i = 0; i < 10; i++) {
      final day = 10 + i;
      final time = DateTime(2026, 10, day, 9);
      await store.upsertEntry(
        id: 'journal_prompt_2026-10-$day',
        timestamp: time,
        moodTag: LocalJournalStore.journalPromptMoodTag(time),
        content: 'Prompt:\nPrompt $i\n\nResponse:\nResponse $i.',
      );
    }

    await tester.pumpWidget(
      _largeTextApp(
        JournalPromptScreen(
          promptService: _FixedPromptService('Today prompt'),
          journalStore: store,
          now: () => DateTime(2026, 10, 20, 9),
          entryIdFactory: (_) => 'journal_prompt_today',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final showAllResponsesButton = find.ancestor(
      of: find.text('Show all saved responses'),
      matching: find.byType(TextButton),
    );
    await tester.scrollUntilVisible(
      showAllResponsesButton,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<TextButton>(showAllResponsesButton).onPressed!();
    await tester.pumpAndSettle();
    final promptZeroTile = find.ancestor(
      of: find.textContaining('Prompt 0'),
      matching: find.byType(ListTile),
    );
    await tester.scrollUntilVisible(
      promptZeroTile,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    tester.widget<ListTile>(promptZeroTile).onTap!();
    await tester.pumpAndSettle();
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Prompt 0', skipOffstage: false), findsOneWidget);
    expect(find.text('Response 0.', skipOffstage: false), findsOneWidget);
  });

  testWidgets(
    'voice save failure keeps editable transcript under nonlinear large text',
    (tester) async {
      final store = _FailingJournalStore();
      await tester.pumpWidget(
        _largeTextApp(
          VoiceJournalScreen(
            journalStore: store,
            service: _FakeVoiceJournalService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Corrected transcript.');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save to journal'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save to journal'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Could not save. Your transcript is still here.',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(find.text('Corrected transcript.', skipOffstage: false),
          findsOneWidget);
      expect(store.writeAttempts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'voice history reopens a saved transcript from the local journal',
    (tester) async {
      final store = LocalJournalStore();
      await store.upsertEntry(
        id: 'voice_saved_1',
        content: 'Earlier voice note.',
        isVoice: true,
      );

      await tester.pumpWidget(
        _largeTextApp(
          VoiceJournalScreen(
            journalStore: store,
            service: _FakeVoiceJournalService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.textContaining('Earlier voice note'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.ancestor(
          of: find.textContaining('Earlier voice note'),
          matching: find.byType(OutlinedButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Earlier voice note.', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.text('Saved transcript reopened.', skipOffstage: false),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'voice history is disabled while active transcripts are streaming',
    (tester) async {
      final store = LocalJournalStore();
      final service = _FakeVoiceJournalService();
      await store.upsertEntry(
        id: 'voice_saved_1',
        content: 'Earlier voice note.',
        isVoice: true,
      );

      await tester.pumpWidget(
        _largeTextApp(
          VoiceJournalScreen(
            journalStore: store,
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start listening'));
      await tester.pumpAndSettle();
      service.emit('live transcript one');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Earlier voice note'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      final historyButton = find.ancestor(
        of: find.textContaining('Earlier voice note'),
        matching: find.byType(OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(historyButton).onPressed, isNull);
      await tester.pumpAndSettle();
      service.emit('live transcript two');
      await tester.pumpAndSettle();
      await service.stopRecording();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save to journal'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save to journal'));
      await tester.pumpAndSettle();

      final saved = await store.findById('voice_saved_1');
      expect(saved?.content, 'Earlier voice note.');
      final entries = await store.findAll(isVoice: true);
      expect(entries.where((entry) => entry.content == 'live transcript two'),
          hasLength(1));
    },
  );

  testWidgets(
    'voice start permission denial is surfaced without replacing saved draft',
    (tester) async {
      final store = LocalJournalStore();
      final service = _FakeVoiceJournalService(
        startResult: false,
        startMessage: 'Microphone permission is required for voice journaling.',
      );
      await store.upsertEntry(
        id: 'voice_saved_1',
        content: 'Earlier voice note.',
        isVoice: true,
      );

      await tester.pumpWidget(
        _largeTextApp(
          VoiceJournalScreen(
            journalStore: store,
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Earlier voice note'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.ancestor(
          of: find.textContaining('Earlier voice note'),
          matching: find.byType(OutlinedButton),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start listening'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Microphone permission'),
        120,
        scrollable: find.byType(Scrollable).first,
      );

      expect(
        find.textContaining('Microphone permission', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.text('Earlier voice note.', skipOffstage: false),
        findsOneWidget,
      );
      expect((await store.findById('voice_saved_1'))?.content,
          'Earlier voice note.');
    },
  );

  testWidgets('voice start unavailable message is not swallowed',
      (tester) async {
    await tester.pumpWidget(
      _largeTextApp(
        VoiceJournalScreen(
          service: _FakeVoiceJournalService(
            startResult: false,
            startMessage: 'Speech-to-text is not available on this device.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start listening'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Speech-to-text is not available'),
      120,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.textContaining('Speech-to-text is not available',
          skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('voice history show-all reaches older saved transcripts',
      (tester) async {
    final store = LocalJournalStore();
    for (var i = 0; i < 10; i++) {
      await store.upsertEntry(
        id: 'voice_saved_$i',
        timestamp: DateTime(2026, 10, 10 + i, 9),
        content: 'Voice note $i.',
        isVoice: true,
      );
    }

    await tester.pumpWidget(
      _largeTextApp(
        VoiceJournalScreen(
          journalStore: store,
          service: _FakeVoiceJournalService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final showAllTranscriptsButton = find.ancestor(
      of: find.text('Show all saved transcripts'),
      matching: find.byType(TextButton),
    );
    await tester.scrollUntilVisible(
      showAllTranscriptsButton,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<TextButton>(showAllTranscriptsButton).onPressed!();
    await tester.pumpAndSettle();
    final voiceZeroTile = find.ancestor(
      of: find.textContaining('Voice note 0'),
      matching: find.byType(ListTile),
    );
    await tester.scrollUntilVisible(
      voiceZeroTile,
      120,
      scrollable: find.byType(Scrollable).last,
    );
    tester.widget<ListTile>(voiceZeroTile).onTap!();
    await tester.pumpAndSettle();

    expect(find.text('Voice note 0.', skipOffstage: false), findsOneWidget);
  });
}

Widget _largeTextApp(Widget home) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(textScaler: _LargeNonlinearTextScaler()),
      child: home,
    ),
  );
}

class _LargeNonlinearTextScaler extends TextScaler {
  const _LargeNonlinearTextScaler();

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  double scale(double fontSize) => fontSize * (fontSize < 20 ? 1.8 : 2.4);
}

class _FixedPromptService extends JournalPromptService {
  _FixedPromptService(this.prompt);

  final String prompt;

  @override
  Future<String> fetchPrompt({String mood = '', DateTime? time}) async {
    return prompt;
  }
}

class _TimePromptService extends JournalPromptService {
  @override
  Future<String> fetchPrompt({String mood = '', DateTime? time}) async {
    return (time?.hour ?? 0) < 12 ? 'Morning prompt' : 'Evening prompt';
  }
}

class _FailingJournalStore extends LocalJournalStore {
  _FailingJournalStore() : super(now: DateTime.now);

  int writeAttempts = 0;

  @override
  Future<JournalEntry?> findById(String id) async => null;

  @override
  Future<JournalEntry> upsertEntry({
    required String id,
    required String content,
    DateTime? timestamp,
    String moodTag = '',
    bool isVoice = false,
  }) async {
    writeAttempts++;
    throw StateError('synthetic write failure');
  }
}

class _FakeVoiceJournalService extends VoiceJournalService {
  _FakeVoiceJournalService({this.startResult = true, this.startMessage});

  final StreamController<String> _stream = StreamController<String>.broadcast();
  final ValueNotifier<bool> _recording = ValueNotifier<bool>(false);
  final bool startResult;
  final String? startMessage;
  String _current = '';

  @override
  Stream<String> get transcriptStream => _stream.stream;

  @override
  ValueListenable<bool> get recording => _recording;

  void emit(String text) {
    _current = text;
    _stream.add(text);
  }

  @override
  Future<bool> startRecording() async {
    final message = startMessage;
    if (message != null) _stream.add(message);
    if (!startResult) return false;
    _recording.value = true;
    return startResult;
  }

  @override
  Future<String> stopRecording() async {
    _recording.value = false;
    return _current;
  }

  @override
  Future<void> dispose() async {
    await _stream.close();
    _recording.dispose();
  }
}
