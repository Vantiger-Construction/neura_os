import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
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
  String reply = 'Clean the filter monthly [1].';
  Completer<String>? delayed;
  late Completer<void> polled;

  setUp(() async {
    fixture = await DataWipeFixture.create();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    calls = [];
    polled = Completer<void>();
    delayed = null;
    reply = 'Clean the filter monthly [1].';
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

  test(
      'approved passages reach only the local adapter and require valid citations',
      () => fixture.run(() async {
            expect(await ask(), ['Clean the filter monthly [1].']);
            final payload = jsonDecode(calls
                .firstWhere((c) => c.method == 'beginOllama')
                .arguments as String);
            final messages = payload['messages'] as List;
            expect(messages.single['content'],
                contains('Clean the filter monthly.'));
            expect(messages.single['content'],
                isNot(contains('Unrelated private text')));
            expect(fixture.networkAttempts, 0);
            reply = 'A fabricated answer [99].';
            expect((await ask()).single,
                contains('could not produce a properly cited answer'));
          }));
  test(
      'removing the source suppresses a late native answer and cancels the request',
      () => fixture.run(() async {
            delayed = Completer<String>();
            final result = expectLater(ask(), throwsA(anything));
            await polled.future;
            shelf.clear();
            delayed!.complete('Must not appear [1].');
            await result;
            expect(calls.any((c) => c.method == 'cancelOllama'), true);
            expect(fixture.networkAttempts, 0);
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
