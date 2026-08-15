import '../models/relationship_suggestion.dart';

class RelationshipInsightService {
  const RelationshipInsightService();

  RelationshipSuggestion? computeOneGoodMove({
    required List<int> recentMoods,
    required bool promisesOutstanding,
    int? daysSinceLastContact,
  }) {
    final reasons = <String>[];

    if (promisesOutstanding) {
      reasons.add('You have open promises that haven’t been cleared.');
      return RelationshipSuggestion(
        title: 'Follow-through time',
        description:
            'You have people waiting on you. Finishing even one small promise builds huge trust.',
        actionLabel: 'Review open commitments',
        reasons: reasons,
      );
    }

    if (recentMoods.length >= 3 &&
        recentMoods.sublist(recentMoods.length - 3).every((m) => m < 0)) {
      reasons.add('Your last 3 mood logs were on the low side.');
      return RelationshipSuggestion(
        title: 'Gentle check-in',
        description:
            'You’ve been carrying a lot. Reaching out to one safe person can soften the load.',
        actionLabel: 'Ask for support',
        reasons: reasons,
      );
    }

    if (daysSinceLastContact != null && daysSinceLastContact >= 7) {
      reasons.add(
          'It’s been over a week since you connected with someone important.');
      return RelationshipSuggestion(
        title: 'Reconnect softly',
        description:
            'A short “thinking of you” message can keep important relationships from drifting.',
        actionLabel: 'Send a gentle ping',
        reasons: reasons,
      );
    }

    if (recentMoods.isNotEmpty && recentMoods.last > 0) {
      reasons.add('Your latest mood was above neutral.');
      return RelationshipSuggestion(
        title: 'Share some good',
        description:
            'You’ve been feeling a bit better. Sharing a win with someone strengthens the bond.',
        actionLabel: 'Share a small win',
        reasons: reasons,
      );
    }

    reasons.add('No strong pattern detected; offering a low-pressure option.');
    return RelationshipSuggestion(
      title: 'Low-pressure nudge',
      description:
          'Pick one person and send: “Thinking of you, hope today treats you kindly.” No expectations.',
      actionLabel: 'Send a kind note',
      reasons: reasons,
    );
  }
}
