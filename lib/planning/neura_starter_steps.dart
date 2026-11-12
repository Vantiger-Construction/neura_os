import '../teaching/neura_teaching_preferences.dart';

/// A user-selected starting size, never a cap on the user's own plan.
/// Templates and existing drafts are not shortened or rewritten.
List<String> neuraStarterSteps(NeuraPlanSize? size) {
  const steps = [
    'Choose the smallest part of this goal to start with',
    'Spend five minutes on that first step',
    'Pause and decide whether to continue or adjust',
  ];
  return List.unmodifiable(steps.take(size?.count ?? 3));
}
