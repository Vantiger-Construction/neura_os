enum NeuraIntentKind {
  recovery,
  weeklyPlan,
  deepFocus,
  organize,
  communicate,
  purchase,
  research,
  general,
}

class NeuraIntent {
  final String rawOutcome;
  final NeuraIntentKind kind;
  final bool isWorkRelated;
  final bool containsSensitiveContent;

  const NeuraIntent({
    required this.rawOutcome,
    required this.kind,
    required this.isWorkRelated,
    required this.containsSensitiveContent,
  });
}

class NeuraIntentClassifier {
  const NeuraIntentClassifier();

  static const maxOutcomeLength = 600;

  NeuraIntent classify(String outcome) {
    final clean = outcome.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) {
      throw ArgumentError.value(outcome, 'outcome', 'must not be empty');
    }
    if (clean.length > maxOutcomeLength) {
      throw const FormatException(
        'Adaptive Intent outcomes must be 600 characters or fewer.',
      );
    }

    final normalized = clean.toLowerCase();
    final kind = _kindFor(normalized);
    final workRelated = _containsAny(normalized, const <String>[
      'work',
      'job',
      'client',
      'project',
      'business',
      'deadline',
      'meeting',
    ]);
    final sensitive = _containsAny(normalized, const <String>[
      'therapy',
      'journal',
      'medical',
      'health',
      'mood',
      'private',
      'trauma',
      'diagnosis',
    ]);

    return NeuraIntent(
      rawOutcome: clean,
      kind: kind,
      isWorkRelated: workRelated,
      containsSensitiveContent: sensitive,
    );
  }

  NeuraIntentKind _kindFor(String normalized) {
    if (_containsAny(normalized, const <String>[
      'buy',
      'purchase',
      'order',
      'checkout',
      'pay for',
    ])) {
      return NeuraIntentKind.purchase;
    }
    if (_containsAny(normalized, const <String>[
      'email',
      'message',
      'text ',
      'contact',
      'send ',
    ])) {
      return NeuraIntentKind.communicate;
    }
    if (_containsAny(normalized, const <String>[
      'overwhelmed',
      'recover',
      'reset',
      'breathe',
      'calm down',
    ])) {
      return NeuraIntentKind.recovery;
    }
    if (_containsAny(normalized, const <String>[
      'focus',
      'deep work',
      'concentrate',
      'finish this',
    ])) {
      return NeuraIntentKind.deepFocus;
    }
    if (_containsAny(normalized, const <String>[
      'week',
      'schedule',
      'calendar',
      'plan my',
    ])) {
      return NeuraIntentKind.weeklyPlan;
    }
    if (_containsAny(normalized, const <String>[
      'research',
      'look up',
      'find out',
      'compare',
    ])) {
      return NeuraIntentKind.research;
    }
    if (_containsAny(normalized, const <String>[
      'organize',
      'sort',
      'clean up',
      'prioritize',
    ])) {
      return NeuraIntentKind.organize;
    }
    return NeuraIntentKind.general;
  }

  bool _containsAny(String value, List<String> candidates) {
    return candidates.any(value.contains);
  }
}
