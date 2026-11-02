import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/conversation_presence_signal.dart';
import 'package:neuro_companion/core/neura_events.dart';

/// Renders emitted events as compact tokens, e.g. `listen+`, `think-`.
List<String> _tokens(List<Object> events) => events.map((e) {
      if (e is NeuraListeningEvent) {
        return e.isListening ? 'listen+' : 'listen-';
      }
      if (e is NeuraThinkingEvent) return e.isThinking ? 'think+' : 'think-';
      return 'other:${e.runtimeType}';
    }).toList();

void main() {
  late List<Object> events;
  late ConversationPresenceSignal signal;

  setUp(() {
    events = <Object>[];
    signal = ConversationPresenceSignal(emit: events.add);
  });

  test('a full voice turn: listen, then think until reply text, then rest', () {
    signal.update(listening: true, awaitingReply: false);
    signal.update(listening: false, awaitingReply: true);
    signal.update(listening: false, awaitingReply: false);

    expect(_tokens(events), ['listen+', 'listen-', 'think+', 'think-']);
    expect(signal.listening, isFalse);
    expect(signal.thinking, isFalse);
  });

  test('repeated identical updates emit nothing new', () {
    for (var i = 0; i < 5; i++) {
      signal.update(listening: false, awaitingReply: true);
    }
    expect(_tokens(events), ['think+']);
  });

  test('listening wins over awaiting a reply, and clears thinking first', () {
    signal.update(listening: false, awaitingReply: true);
    signal.update(listening: true, awaitingReply: true);

    expect(_tokens(events), ['think+', 'think-', 'listen+']);
    expect(signal.thinking, isFalse);
    expect(signal.listening, isTrue);
  });

  test('suppression (Safe Mode or disposal) forces both states off', () {
    signal.update(listening: true, awaitingReply: false);
    signal.update(listening: true, awaitingReply: true, suppressed: true);
    signal.update(listening: false, awaitingReply: true, suppressed: true);

    expect(_tokens(events), ['listen+', 'listen-']);
    expect(signal.listening, isFalse);
    expect(signal.thinking, isFalse);
  });

  test('reset only turns off what this signal turned on', () {
    signal.reset();
    expect(events, isEmpty);

    signal.update(listening: false, awaitingReply: true);
    signal.reset();
    expect(_tokens(events), ['think+', 'think-']);
  });

  test('emits only presence events, never content', () {
    signal.update(listening: true, awaitingReply: false);
    signal.update(listening: false, awaitingReply: true);
    signal.reset();

    expect(
      events.every((e) => e is NeuraListeningEvent || e is NeuraThinkingEvent),
      isTrue,
    );
  });
}
