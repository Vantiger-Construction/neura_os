import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/relationships/services/relationship_insight_service.dart';

void main() {
  const insight = RelationshipInsightService();

  test('a reconnect nudge names the person it has been longest since', () {
    final suggestion = insight.computeOneGoodMove(
      recentMoods: const [0, 0, 0],
      promisesOutstanding: false,
      daysSinceLastContact: 12,
      personName: 'Marcus',
    )!;
    expect(suggestion.title, 'Reconnect with Marcus');
    expect(suggestion.description, contains('12 days'));
    expect(suggestion.actionLabel, 'Send Marcus a gentle ping');
    expect(suggestion.reasons.single, contains('Marcus'));
  });

  test('without a name the nudge stays general', () {
    for (final name in <String?>[null, '', '   ']) {
      final suggestion = insight.computeOneGoodMove(
        recentMoods: const [0, 0, 0],
        promisesOutstanding: false,
        daysSinceLastContact: 12,
        personName: name,
      )!;
      expect(suggestion.title, 'Reconnect softly');
    }
  });

  test('a recent contact is not a reason to reconnect', () {
    final suggestion = insight.computeOneGoodMove(
      recentMoods: const [0, 0, 0],
      promisesOutstanding: false,
      daysSinceLastContact: 3,
      personName: 'Marcus',
    )!;
    expect(suggestion.title, isNot(contains('Marcus')));
  });
}
