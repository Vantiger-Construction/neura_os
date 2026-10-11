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
  final StreamController<String> _stream = StreamController<String>.broadcast();
  final ValueNotifier<bool> _recording = ValueNotifier<bool>(false);

  @override
  Stream<String> get transcriptStream => _stream.stream;

  @override
  ValueListenable<bool> get recording => _recording;

  @override
  Future<void> dispose() async {
    await _stream.close();
    _recording.dispose();
  }
}
