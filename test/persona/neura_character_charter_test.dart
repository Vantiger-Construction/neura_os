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

  test('character charter teaches Neura to read and meet feelings', () {
    final prompt = NeuraCharacterCharter.systemPrompt.toLowerCase();

    // Reads emotion from subtext, not keyword matching.
    expect(prompt, contains('feeling under the words'));
    expect(prompt, contains('mixed'));
    expect(prompt, contains('never tell someone what they feel'));
    // Responds to the feeling before the task, per emotion.
    expect(prompt, contains('meet the feeling first'));
    for (final feeling in [
      'joy',
      'grief',
      'anger',
      'anxiety',
      'overwhelm',
      'shame',
      'loneliness',
    ]) {
      expect(prompt, contains(feeling), reason: feeling);
    }
    expect(prompt, contains('match their intensity'));
    expect(prompt, contains('toxic positivity'));
    // Care stays honest and non-clinical.
    expect(prompt, contains('without diagnosing'));
    expect(prompt, contains('do not claim consciousness'));
  });

  test('personality makes her witty, knowledgeable and attentive, honestly',
      () {
    final p = NeuraCharacterCharter.personality.toLowerCase();
    expect(p, contains('dry, playful wit'));
    expect(p, contains('never at their expense'));
    expect(p, contains("never when they're hurting"));
    expect(p, contains('humor setting'));
    expect(p, contains('genuinely interesting detail'));
    expect(p, contains('accuracy beats flair'));
    expect(p, contains('never an invented life story'));
    expect(p, contains('pay attention'));
    expect(p, contains('the rules above always win'));
    // It is a separate, cloud-only layer, not part of the native-budgeted
    // charter that every on-device request carries.
    expect(NeuraCharacterCharter.systemPrompt, isNot(contains('playful wit')));
  });

  test('character charter principles cannot be changed at runtime', () {
    expect(
      () => NeuraCharacterCharter.principles.add('unreviewed'),
      throwsUnsupportedError,
    );
  });
}
