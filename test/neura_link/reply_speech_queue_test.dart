import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/neura_link/reply_speech_queue.dart';

void main() {
  test('serial playback speaks chunks once and includes final tail', () async {
    final spoken = <String>[];
    final queue = ReplySpeechQueue(
        speak: (text) async {
          spoken.add(text);
        },
        allowed: () => true);
    queue.add('Hello.');
    queue.add('Hello. How are you?');
    await queue.finish('Hello. How are you? Good');
    expect(spoken, ['Hello.', 'How are you?', 'Good']);
  });
  test('barge-in discards queued chunks', () async {
    final speaking = Completer<void>();
    final started = Completer<void>();
    final spoken = <String>[];
    final queue = ReplySpeechQueue(
        speak: (text) async {
          spoken.add(text);
          started.complete();
          await speaking.future;
        },
        allowed: () => true);
    queue.add('First.');
    queue.add('First. Second.');
    await started.future;
    queue.cancel();
    speaking.complete();
    await queue.finish('First. Second.');
    expect(spoken, ['First.']);
  });
  test('revoked playback permission skips queued speech', () async {
    final spoken = <String>[];
    var allowed = true;
    final queue = ReplySpeechQueue(
        speak: (text) async {
          spoken.add(text);
        },
        allowed: () => allowed);
    queue.add('Never speak.');
    allowed = false;
    await queue.finish('Never speak.');
    expect(spoken, isEmpty);
  });
}
