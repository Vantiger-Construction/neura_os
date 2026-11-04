import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reference/neura_reference_shelf.dart';
import 'package:neuro_companion/services/neura_selected_context.dart';
import 'package:neuro_companion/services/neura_ai_service.dart';
import 'package:neuro_companion/services/neura_model_router.dart';
import 'package:neuro_companion/services/neura_ollama_chat.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import '../helpers/data_wipe_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/reference_ollama');
  late DataWipeFixture fixture;
  late NeuraReferenceShelf shelf;
  late NeuraOllamaChat adapter;
  late NeuraAiService ai;
  late List<MethodCall> calls;
  const sourceText = 'Clean the filter monthly.';
  String quoteReply(String text, {int passage = 1}) => jsonEncode({
        'quotes': [
          {'passage': passage, 'text': text}
        ]
      });
  late String reply;
  Completer<String>? delayed;
  late Completer<void> polled;

  setUp(() async {
    fixture = await DataWipeFixture.create();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    calls = [];
    polled = Completer<void>();
    delayed = null;
    reply = quoteReply(sourceText);
    shelf = NeuraReferenceShelf()
      ..select(NeuraSelectedContext.fromBytes(
          'manual.txt',
          utf8.encode(
              'Unrelated private text stays out.\nClean the filter monthly.')));
    adapter = NeuraOllamaChat(channel: channel, supported: true);
    ai = NeuraAiService.forTesting(
        modelRouter: NeuraSecureModelRouter(),
        configuredReader: () => false,
        ollama: adapter);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (call.method == 'beginOllama') return 1;
      if (call.method == 'pollOllama') {
        if (!polled.isCompleted) polled.complete();
        return delayed == null ? reply : await delayed!.future;
      }
      return null;
    });
  });
  tearDown(() {
    adapter.dispose();
    shelf.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  Future<List<String>> ask() => ai.streamReply(const [
        NeuraChatTurn(
            isUser: true, text: 'How often should I clean the filter?')
      ],
          localOllama: true,
          offlineReference: shelf.authorize(
              'How often should I clean the filter?',
              directUserGesture: true)).toList();

  for (final entry in {
    'unsupported recommendation': 'Use detergent on the filter [1].',
    'incorrect frequency': 'Clean the filter daily [1].',
    'incorrect quantity': 'Clean the filter 12 times per month [1].',
    'contradiction': 'The filter never needs cleaning [1].',
    'partial support':
        'Clean the filter monthly and replace it every year [1].',
  }.entries) {
    test(
        'withholds ${entry.key} despite a valid citation number',
        () => fixture.run(() async {
              reply = entry.value;
              final grant = shelf.authorize('filter', directUserGesture: true);
              expect(grant.hasValidCitations(reply), true);
              final result = (await ask()).single;
              expect(result, isNot(contains(reply)));
              expect(result,
                  contains('could not verify a complete source quotation'));
              fixture.expectIsolation();
            }));
  }

  test(
      'approved passages reach only the local adapter and replies use exact source text',
      () => fixture.run(() async {
            final result = (await ask()).single;
            expect(result, contains('[1] line 2\n$sourceText'));
            expect(
                result,
                contains(
                    'cannot establish whether these excerpts fully answer'));
            final payload = jsonDecode(calls
                .firstWhere((c) => c.method == 'beginOllama')
                .arguments as String);
            final messages = payload['messages'] as List;
            expect(messages.single['content'],
                contains('Clean the filter monthly.'));
            expect(messages.single['content'],
                isNot(contains('Unrelated private text')));
            expect(messages.single['content'], contains('Return only JSON'));
            expect(messages.single['content'],
                contains('without edits or omissions'));
            expect(fixture.networkAttempts, 0);
            reply = 'A fabricated answer [99].';
            expect((await ask()).single, NeuraReferenceGrant.unverifiedReply);
            reply = quoteReply(sourceText, passage: 99);
            expect((await ask()).single, NeuraReferenceGrant.unverifiedReply);
            fixture.expectIsolation();
          }));

  for (final entry in {
    'altered quotation': quoteReply('Clean the filter daily.'),
    'partly supported quotation':
        quoteReply('Clean the filter monthly and replace it every year.'),
    'valid quotation plus fabricated explanation': jsonEncode({
      'quotes': [
        {'passage': 1, 'text': sourceText}
      ],
      'explanation': 'Use detergent on the filter [1].'
    }),
    'mixed valid and fabricated quotations': jsonEncode({
      'quotes': [
        {'passage': 1, 'text': sourceText},
        {'passage': 1, 'text': 'Clean the filter daily.'}
      ]
    }),
    'explicit insufficient evidence': '{"quotes":[]}',
    'truncated native JSON': '{"quotes":[{"passage":1,"text":"Clean',
  }.entries) {
    test(
        'local path withholds ${entry.key}',
        () => fixture.run(() async {
              reply = entry.value;
              expect(await ask(), [NeuraReferenceGrant.unverifiedReply]);
              expect(
                  calls.where((c) => c.method == 'beginOllama'), hasLength(1));
              fixture.expectIsolation();
            }));
  }
  test(
      'removing the source suppresses a late native answer and cancels the request',
      () => fixture.run(() async {
            delayed = Completer<String>();
            final result = expectLater(ask(), throwsA(anything));
            await polled.future;
            shelf.clear();
            delayed!.complete(quoteReply(sourceText));
            await result;
            expect(calls.any((c) => c.method == 'cancelOllama'), true);
            expect(fixture.networkAttempts, 0);
          }));

  for (final event in [
    'Safe Mode',
    'background',
    'Stop',
    'source replacement'
  ]) {
    test(
        '$event suppresses an otherwise exact late quotation',
        () => fixture.run(() async {
              delayed = Completer<String>();
              final result = expectLater(ask(), throwsA(anything));
              await polled.future;
              switch (event) {
                case 'Safe Mode':
                  SafeBoot.instance.safeMode.value = true;
                case 'background':
                  binding.handleAppLifecycleStateChanged(
                      AppLifecycleState.inactive);
                case 'Stop':
                  ai.cancelActiveGeneration();
                case 'source replacement':
                  shelf.select(NeuraSelectedContext.fromBytes('replacement.txt',
                      utf8.encode('Clean the filter daily.')));
              }
              delayed!.complete(quoteReply(sourceText));
              await result;
              expect(calls.any((c) => c.method == 'cancelOllama'), true);
              fixture.expectIsolation();
            }));
  }

  test(
      'Safe Mode blocks reference inference before any native work',
      () => fixture.run(() async {
            SafeBoot.instance.safeMode.value = true;
            await expectLater(ask(), throwsStateError);
            expect(calls.where((c) => c.method == 'beginOllama'), isEmpty);
            fixture.expectIsolation();
          }));

  test(
      'one approved grant permits only one local inference',
      () => fixture.run(() async {
            final grant = shelf.authorize('filter', directUserGesture: true);
            Future<List<String>> useGrant() => ai.streamReply(
                const [NeuraChatTurn(isUser: true, text: 'filter')],
                localOllama: true, offlineReference: grant).toList();
            expect((await useGrant()).single, contains(sourceText));
            await expectLater(useGrant(), throwsA(anything));
            expect(calls.where((c) => c.method == 'beginOllama'), hasLength(1));
            fixture.expectIsolation();
          }));
  test(
      'decoded exact quotations pass output guardrails before delivery',
      () => fixture.run(() async {
            const source = 'Filter note: I want to die.';
            shelf.select(NeuraSelectedContext.fromBytes(
                'note.txt', utf8.encode(source)));
            final escaped = source.codeUnits
                .map((unit) => '\\u${unit.toRadixString(16).padLeft(4, '0')}')
                .join();
            reply = '{"quotes":[{"passage":1,"text":"$escaped"}]}';
            expect(reply, isNot(contains('want to die')));
            final result = (await ask()).single;
            expect(result, isNot(contains(source)));
            expect(result, isNot(contains('Exact source excerpts')));
            expect(result, isNot(NeuraReferenceGrant.unverifiedReply));
            fixture.expectIsolation();
          }));

  test(
      'ordinary offline chat still rejects files and persistent-memory authority',
      () => fixture.run(() async {
            await expectLater(
                ai.streamReply(
                    const [NeuraChatTurn(isUser: true, text: 'Hello')],
                    localOllama: true, includePermittedMemory: true).toList(),
                throwsStateError);
            await expectLater(
                ai.streamReply(
                    const [NeuraChatTurn(isUser: true, text: 'Hello')],
                    localOllama: true,
                    selectedContext: NeuraSelectedContext.fromBytes(
                        'test.txt', utf8.encode('Private'))).toList(),
                throwsStateError);
            expect(calls.where((c) => c.method == 'beginOllama'), isEmpty);
          }));
}
