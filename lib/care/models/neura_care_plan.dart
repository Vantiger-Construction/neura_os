import 'package:flutter/foundation.dart';

enum NeuraCareNeed { settle, rest, move, nourish, connect, focus }

extension NeuraCareNeedCopy on NeuraCareNeed {
  String get label => switch (this) {
        NeuraCareNeed.settle => 'Settle my body',
        NeuraCareNeed.rest => 'Reduce the load',
        NeuraCareNeed.move => 'Gently move',
        NeuraCareNeed.nourish => 'Water or food',
        NeuraCareNeed.connect => 'Reach someone',
        NeuraCareNeed.focus => 'Find one next step',
      };
}

@immutable
class NeuraCareCheckIn {
  const NeuraCareCheckIn({
    required this.mood0to10,
    required this.energy0to10,
    required this.overwhelm0to10,
    required this.need,
    this.feelsUnsafe = false,
  })  : assert(mood0to10 >= 0 && mood0to10 <= 10),
        assert(energy0to10 >= 0 && energy0to10 <= 10),
        assert(overwhelm0to10 >= 0 && overwhelm0to10 <= 10);

  final int mood0to10;
  final int energy0to10;
  final int overwhelm0to10;
  final NeuraCareNeed need;
  final bool feelsUnsafe;
}

enum NeuraCareActionKind {
  grounding,
  rest,
  movement,
  nourishment,
  connection,
  focus,
  immediateSupport,
}

@immutable
class NeuraCareAction {
  const NeuraCareAction({
    required this.id,
    required this.kind,
    required this.title,
    required this.guidance,
    required this.durationMinutes,
  });

  final String id;
  final NeuraCareActionKind kind;
  final String title;
  final String guidance;
  final int durationMinutes;
}

@immutable
class NeuraCarePlan {
  const NeuraCarePlan({
    required this.summary,
    required this.primaryAction,
    required this.alternativeAction,
    this.requiresImmediateSupport = false,
  });

  final String summary;
  final NeuraCareAction primaryAction;
  final NeuraCareAction alternativeAction;
  final bool requiresImmediateSupport;
}
