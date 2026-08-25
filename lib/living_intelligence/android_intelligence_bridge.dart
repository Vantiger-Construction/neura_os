import 'neura_safety_policy.dart';

class NeuraAndroidFunctionDecision {
  const NeuraAndroidFunctionDecision({
    required this.allowed,
    required this.requiresInAppReview,
    required this.reason,
  });

  final bool allowed;
  final bool requiresInAppReview;
  final String reason;

  bool get grantsExecutionAuthority => false;
}

/// Allowlisted Android intelligence-system surface.
///
/// Requests can open safe app surfaces or prepare an in-app draft. They cannot
/// export private data, contact people, move money, delete data, or execute a
/// capability directly.
class NeuraAndroidIntelligenceBridge {
  const NeuraAndroidIntelligenceBridge();

  static const openNeura = 'open_neura';
  static const openRoom = 'open_room';
  static const startRitual = 'start_selected_ritual';
  static const showQuests = 'show_user_quests';
  static const draftQuest = 'draft_quest_for_review';
  static const openSafeModeControls = 'open_safe_mode_controls';

  NeuraAndroidFunctionDecision evaluate({
    required String functionId,
    required NeuraSafetyContext context,
    required bool safeModeActive,
  }) {
    if (!_allowlist.contains(functionId)) {
      return const NeuraAndroidFunctionDecision(
        allowed: false,
        requiresInAppReview: false,
        reason: 'The Android function is not allowlisted.',
      );
    }

    if (safeModeActive) {
      final safeSurface =
          functionId == openNeura || functionId == openSafeModeControls;
      return NeuraAndroidFunctionDecision(
        allowed: safeSurface,
        requiresInAppReview: false,
        reason: safeSurface
            ? 'Safe Mode permits access to recovery controls.'
            : 'Safe Mode blocks this Android function.',
      );
    }

    if (context.recoveryMode &&
        functionId != openSafeModeControls &&
        functionId != openNeura) {
      return const NeuraAndroidFunctionDecision(
        allowed: false,
        requiresInAppReview: false,
        reason: 'Recovery mode permits only recovery-safe surfaces.',
      );
    }

    if (functionId == draftQuest) {
      if (!context.directUserGesture) {
        return const NeuraAndroidFunctionDecision(
          allowed: false,
          requiresInAppReview: true,
          reason: 'Draft creation requires a direct user gesture.',
        );
      }
      return const NeuraAndroidFunctionDecision(
        allowed: true,
        requiresInAppReview: true,
        reason: 'A draft may be prepared for review inside Neura.',
      );
    }

    return const NeuraAndroidFunctionDecision(
      allowed: true,
      requiresInAppReview: false,
      reason: 'The request opens an allowlisted local Neura surface.',
    );
  }

  static const Set<String> _allowlist = {
    openNeura,
    openRoom,
    startRitual,
    showQuests,
    draftQuest,
    openSafeModeControls,
  };
}
