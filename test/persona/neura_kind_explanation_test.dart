import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/persona/models/neura_kind_explanation.dart';

void main() {
  test('spoken brief is humble and preserves approval', () {
    final brief = NeuraKindExplanation.spokenBrief(
      title: 'A gentle next step',
      body: 'Would a short reset help?',
      requiresApproval: true,
    );

    expect(brief, contains('may not have the full picture'));
    expect(brief, contains('choose what feels right for you'));
    expect(brief, contains('only a suggestion'));
    expect(brief, contains('wait for your approval'));
  });

  test('non-mutating suggestions still preserve client control', () {
    final statement = NeuraKindExplanation.controlStatement(
      requiresApproval: false,
    );

    expect(statement, contains('only a suggestion'));
    expect(statement, contains('Nothing will happen unless you choose'));
  });
}
