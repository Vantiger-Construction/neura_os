import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_fact_check.dart';

void main() {
  test('factual questions answered with specifics get the memory caveat', () {
    expect(
      NeuraFactCheck.caveatFor(
        'When did the Berlin Wall fall?',
        'It fell on 9 November 1989.',
      ),
      NeuraFactCheck.memoryCaveat,
    );
    expect(
      NeuraFactCheck.caveatFor(
        'How many people live in Canada?',
        'About 40 million people.',
      ),
      NeuraFactCheck.memoryCaveat,
    );
  });

  test('any dose gets the pharmacist line', () {
    expect(
      NeuraFactCheck.caveatFor(
        'How much ibuprofen can I take?',
        'Adults often take 200 to 400 mg.',
      ),
      NeuraFactCheck.doseCaveat,
    );
  });

  test('feelings, chat and answers without specifics stay as they are', () {
    expect(
      NeuraFactCheck.caveatFor(
        'I feel so tired today',
        'That sounds hard. Two things might help.',
      ),
      isNull,
    );
    expect(
      NeuraFactCheck.caveatFor(
        'Who could I talk to about this?',
        'A trusted friend or a counsellor could help.',
      ),
      isNull,
    );
    expect(
      NeuraFactCheck.caveatFor('Tell me a joke', 'Why did 2 cows laugh?'),
      isNull,
    );
    expect(NeuraFactCheck.caveatFor('When is it?', ''), isNull);
  });
}
