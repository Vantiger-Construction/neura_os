import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_style_memory.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NeuraStyleMemory memory;
  var now = DateTime(2026, 11, 1);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    await NeuraPrefsCache.prefs.remove(NeuraStyleMemory.storageKey);
    now = DateTime(2026, 11, 1);
    memory = NeuraStyleMemory(
      encrypt: (json) async =>
          'sealed:${base64Encode(utf8.encode(jsonEncode(json)))}',
      decrypt: (blob) async => jsonDecode(
        utf8.decode(base64Decode(blob.substring('sealed:'.length))),
      ) as Map<String, dynamic>,
      now: () => now,
    );
  });

  test('nothing learned means no prompt section', () async {
    expect(await memory.promptSection('Hello'), '');
  });

  test('liked replies become tone examples, closest topic first', () async {
    await memory.rate(
      prompt: 'I could not sleep again last night',
      reply: 'That sounds exhausting. Want to try a slow breath together?',
      liked: true,
    );
    now = now.add(const Duration(hours: 1));
    await memory.rate(
      prompt: 'What should I cook tonight?',
      reply: 'Something warm and easy, like soup.',
      liked: true,
    );
    final stored =
        NeuraPrefsCache.prefs.getString(NeuraStyleMemory.storageKey)!;
    expect(stored, startsWith('sealed:'));
    expect(stored, isNot(contains('soup')));

    final section = await memory.promptSection('Still struggling to sleep');
    final lines = section.split('\n');
    expect(lines.first, contains('Match their tone and length'));
    expect(lines[1], contains('could not sleep'));
    expect(lines[2], contains('cook tonight'));
    expect(utf8.encode(section).length,
        lessThanOrEqualTo(NeuraStyleMemory.maxSectionBytes));
  });

  test('turn cue budget keeps UTF-8 examples whole and reserves the hint',
      () async {
    for (final reply in ['short', 'closer', '🌧' * 75]) {
      await memory.rate(prompt: 'Fictional rain', reply: reply, liked: true);
      now = now.add(const Duration(minutes: 1));
    }
    final section = await memory.promptSection('rain', byteBudget: 220);
    expect(utf8.encode(section).length, lessThanOrEqualTo(220));
    expect(section, contains('closer'));
    expect(section, isNot(contains('🌧')));
    expect(section, endsWith('They prefer short replies.'));
    expect(await memory.promptSection('rain', byteBudget: 1), isEmpty);
  });

  test('a thumbs down removes that reply from the examples', () async {
    const reply = 'Here is a very long answer.';
    await memory.rate(prompt: 'Hi', reply: reply, liked: true);
    await memory.rate(prompt: 'Hi', reply: reply, liked: false);
    expect(await memory.likedCount, 0);
  });

  test('ratings teach a length preference', () {
    final long = [
      for (var i = 0; i < 3; i++) (liked: false, words: 150),
    ];
    expect(NeuraStyleMemory.lengthHint(long), 'They prefer short replies.');
    final short = [
      for (var i = 0; i < 3; i++) (liked: true, words: 20),
    ];
    expect(NeuraStyleMemory.lengthHint(short), 'They prefer short replies.');
    final detailed = [
      for (var i = 0; i < 3; i++) (liked: true, words: 160),
    ];
    expect(
      NeuraStyleMemory.lengthHint(detailed),
      'They like fuller, more detailed replies.',
    );
    expect(NeuraStyleMemory.lengthHint(short.take(2).toList()), '');
  });

  test('examples are bounded and forget clears everything', () async {
    for (var i = 0; i < NeuraStyleMemory.maxLiked + 4; i++) {
      await memory.rate(prompt: 'Q$i', reply: 'Reply $i. ' * 80, liked: true);
    }
    expect(await memory.likedCount, NeuraStyleMemory.maxLiked);
    final section = await memory.promptSection('Q13');
    expect(utf8.encode(section).length,
        lessThanOrEqualTo(NeuraStyleMemory.maxSectionBytes));
    await memory.forget();
    expect(await memory.promptSection('Q13'), '');
  });
}
