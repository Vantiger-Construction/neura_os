import '../models/neura_care_plan.dart';

/// Builds a small care plan from values the person explicitly provides.
///
/// This service is deterministic and content-free. It does not inspect journal
/// text, infer a diagnosis, call a model, or start voice/background services.
class NeuraCareLoopService {
  const NeuraCareLoopService();

  NeuraCarePlan buildPlan(NeuraCareCheckIn checkIn) {
    if (checkIn.feelsUnsafe) return _immediateSupportPlan;

    final requested = _actionFor(checkIn.need);
    final primary = checkIn.overwhelm0to10 >= 8
        ? _grounding
        : checkIn.energy0to10 <= 2 && checkIn.need == NeuraCareNeed.focus
            ? _rest
            : requested;
    final alternative = _alternativeFor(checkIn, primary);

    return NeuraCarePlan(
      summary: _summaryFor(checkIn, primary),
      primaryAction: primary,
      alternativeAction: alternative,
    );
  }

  NeuraCareAction _actionFor(NeuraCareNeed need) => switch (need) {
        NeuraCareNeed.settle => _grounding,
        NeuraCareNeed.rest => _rest,
        NeuraCareNeed.move => _movement,
        NeuraCareNeed.nourish => _nourishment,
        NeuraCareNeed.connect => _connection,
        NeuraCareNeed.focus => _focus,
      };

  NeuraCareAction _alternativeFor(
    NeuraCareCheckIn checkIn,
    NeuraCareAction primary,
  ) {
    final candidate = switch ((checkIn.mood0to10, checkIn.energy0to10)) {
      (<= 3, _) => _connection,
      (_, <= 3) => _rest,
      _ => _nourishment,
    };
    if (candidate.id != primary.id) return candidate;
    return primary.id == _grounding.id ? _rest : _grounding;
  }

  String _summaryFor(
    NeuraCareCheckIn checkIn,
    NeuraCareAction primary,
  ) {
    if (checkIn.overwhelm0to10 >= 8) {
      return 'The load feels high. Steady first; decisions can wait.';
    }
    if (checkIn.energy0to10 <= 2) {
      return 'Energy is limited. Make the next step smaller, not harder.';
    }
    if (checkIn.mood0to10 <= 3) {
      return 'This is a low moment. You do not have to solve it alone.';
    }
    return 'Start with ${primary.title.toLowerCase()}. One step is enough.';
  }

  static const _grounding = NeuraCareAction(
    id: 'orient_for_one_minute',
    kind: NeuraCareActionKind.grounding,
    title: 'Orient for one minute',
    guidance: 'Put both feet somewhere supported. Name three things you see, '
        'three things you feel, and three things you hear. Let each exhale '
        'be comfortable and unforced.',
    durationMinutes: 1,
  );

  static const _rest = NeuraCareAction(
    id: 'lower_one_demand',
    kind: NeuraCareActionKind.rest,
    title: 'Lower one demand',
    guidance: 'Choose one thing that can safely wait. Give yourself ten quiet '
        'minutes without needing to improve, decide, or perform.',
    durationMinutes: 10,
  );

  static const _movement = NeuraCareAction(
    id: 'gentle_movement',
    kind: NeuraCareActionKind.movement,
    title: 'Try two minutes of gentle movement',
    guidance: 'Stand, stretch, or walk at a comfortable pace. Stop if it feels '
        'wrong for your body; the goal is a small state change, not a workout.',
    durationMinutes: 2,
  );

  static const _nourishment = NeuraCareAction(
    id: 'water_and_fuel',
    kind: NeuraCareActionKind.nourishment,
    title: 'Check water and regular fuel',
    guidance:
        'Have some water and, if it fits your needs, something familiar to '
        'eat. Keep it simple and follow any medical guidance you already use.',
    durationMinutes: 5,
  );

  static const _connection = NeuraCareAction(
    id: 'reach_one_person',
    kind: NeuraCareActionKind.connection,
    title: 'Reach toward one safe person',
    guidance:
        'Try: “I could use a little support. Are you available to talk or sit '
        'with me?” You choose whether and how to send it.',
    durationMinutes: 5,
  );

  static const _focus = NeuraCareAction(
    id: 'one_visible_step',
    kind: NeuraCareActionKind.focus,
    title: 'Choose one visible next step',
    guidance:
        'Pick a task that takes ten minutes or less. Do only its first visible '
        'step, then decide whether to continue.',
    durationMinutes: 10,
  );

  static const _immediateSupportPlan = NeuraCarePlan(
    summary:
        'Your safety matters more than finishing this check-in. Get another '
        'person involved now.',
    primaryAction: NeuraCareAction(
      id: 'get_human_support_now',
      kind: NeuraCareActionKind.immediateSupport,
      title: 'Get human support now',
      guidance:
          'If you may act on thoughts of harming yourself or someone else, or '
          'you are in immediate danger, call local emergency services now. In '
          'the U.S. and its territories, call or text 988.',
      durationMinutes: 0,
    ),
    alternativeAction: NeuraCareAction(
      id: 'move_toward_safety',
      kind: NeuraCareActionKind.connection,
      title: 'Move toward safety',
      guidance:
          'Go near a trusted person or public place if you can. Put distance '
          'between you and anything you could use to hurt yourself or others.',
      durationMinutes: 0,
    ),
    requiresImmediateSupport: true,
  );
}
