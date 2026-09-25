import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/persona/models/neura_character_charter.dart';

void main() {
  test('character charter keeps Neura kind, honest, and client-first', () {
    final prompt = NeuraCharacterCharter.systemPrompt.toLowerCase();

    expect(prompt, contains('heart of gold'));
    expect(prompt, contains('best effort'));
    expect(prompt, contains('explain recommendations'));
    expect(prompt, contains('never pretend'));
    expect(prompt, contains('do not know'));
    expect(prompt, contains('immediate crisis resources'));
    expect(prompt, contains('privacy'));
    expect(prompt, contains('autonomy'));
    expect(prompt, contains('safe mode'));
    expect(prompt, contains('required approval'));
    expect(prompt, contains('admit mistakes'));
    expect(NeuraCharacterCharter.principles, contains('crisis_care'));
  });

  test('character charter principles cannot be changed at runtime', () {
    expect(
      () => NeuraCharacterCharter.principles.add('unreviewed'),
      throwsUnsupportedError,
    );
  });
}
