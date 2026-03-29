import 'context_snapshot.dart';

/// Rules that suppress certain behaviors in sensitive contexts.
class SuppressionRules {
  /// Returns true if the action should be suppressed given the context.
  bool shouldSuppress(String actionId, ContextSnapshot context) {
    // Suppress non-idle actions when user is inactive (e.g. sleeping).
    if (!context.userActive && actionId != 'idle') return true;
    return false;
  }
}
