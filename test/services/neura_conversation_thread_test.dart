import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_conversation_thread.dart';
import 'package:neuro_companion/services/neura_offline_budget.dart';

void main() {
  test('thread is opt-in and uses user text with a replaceable correction', () {
    final thread = NeuraConversationThread();
    thread.observeUserTurn('Plan Tuesday');
    expect(thread.context, isEmpty);
    thread.enabled = true;
    thread.observeUserTurn('Plan Tuesday');
    thread.observeUserTurn('Actually, make that Thursday');
    thread.observeUserTurn('Actually, make that Friday');
    expect(thread.context, contains('Friday'));
    expect(thread.context, isNot(contains('Thursday')));
    expect(thread.topic, 'Plan Tuesday');
    thread.clear();
    expect(thread.context, isEmpty);
    expect(thread.enabled, false);
  });
  test('UTF-8 bounds preserve complete corrections and validate explicit edits',
      () {
    final thread = NeuraConversationThread()..enabled = true;
    thread.observeUserTurn('A small goal');
    thread.observeUserTurn('Actually ${'🙂' * 100}');
    expect(thread.correction, isEmpty);
    expect(() => thread.update('🙂' * 41, ''), throwsFormatException);
    expect(thread.topic, 'A small goal');
  });
  test(
      'brief survives trimmed history without increasing native message or byte limits',
      () {
    final thread = NeuraConversationThread()..enabled = true;
    thread.update(
        'Prepare for a job interview', 'Actually, the interview is Friday');
    final messages = [
      for (var i = 0; i < 30; i++)
        {
          'role': i.isOdd ? 'user' : 'assistant',
          'content': 'Turn $i ${'x' * 100}'
        }
    ];
    for (final budget in NeuraOfflineBudget.values) {
      final retained = budget.retain(messages, threadContext: thread.context);
      expect(retained.first['content'], contains('Friday'));
      expect(retained.last['content'], messages.last['content']);
      expect(retained.length, lessThanOrEqualTo(8));
      expect(
          retained.fold<int>(
              0, (n, m) => n + utf8.encode(m['content'] as String).length),
          lessThanOrEqualTo(budget.contextBytes));
    }
  });
  test('newest message wins when there is no space for a brief', () {
    final retained = NeuraOfflineBudget.compact.retain([
      {'role': 'user', 'content': 'x' * 750}
    ], threadContext: 'earlier detail');
    expect(retained.single['content'], 'x' * 750);
  });
}
