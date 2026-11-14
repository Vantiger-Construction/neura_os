/// How much proactive attention a penthouse room tolerates.
///
/// Rooms are where Neura and the user *are*, so they are an attention signal
/// in their own right: a room meant for private writing should not be
/// interrupted by a cheerful quest suggestion just because the dashboard
/// happened to evaluate candidates there.
///
/// Values are declared from least to most protective;
/// [NeuraRoomAttentionPolicy.stricter] relies on that order.
enum NeuraRoomAttention {
  /// Normal proactive behavior; the rest of the Autonomy Kernel decides.
  open,

  /// Grounding spaces. Only low-disruption candidates may surface.
  calm,

  /// Private or protected spaces. Proactive candidates stay silent.
  private,
}

/// Room-aware, tightening-only attention boundary for proactive intelligence.
///
/// Consulted by `NeuraAutonomyKernel`. Like the Personal Constitution check,
/// it can only turn a candidate stricter (suppressed); it never makes an
/// outcome more permissive. Candidates at or above [urgentOverride] urgency
/// pass through, matching how the kernel already treats deep-work and
/// wind-down focus modes, so genuinely urgent care can still reach the user.
class NeuraRoomAttentionPolicy {
  const NeuraRoomAttentionPolicy._();

  /// Same urgency bar the kernel uses to let urgent candidates through a
  /// protected focus mode.
  static const double urgentOverride = 0.85;

  /// Highest disruption a non-urgent candidate may carry in a [calm] room.
  static const double calmMaxDisruption = 0.35;

  /// Room ids come from `NeuraRoom.id`. Rooms not listed here are [open],
  /// which is also what `NeuraRoom.fromId` falls back to (the penthouse).
  static const Map<String, NeuraRoomAttention> _byRoomId = {
    // "A slower place for reflection and private writing."
    'reflection_bay': NeuraRoomAttention.private,
    // "A protected room for memory, meaning, and future-you."
    'legacy_vault': NeuraRoomAttention.private,
    // "A steady room for feelings, care, and grounding."
    'mood_den': NeuraRoomAttention.calm,
  };

  /// The built-in attention for [roomId]. User choices can only make a room
  /// stricter than this; see [effectiveFor].
  static NeuraRoomAttention forRoom(String? roomId) {
    final id = roomId?.trim();
    if (id == null || id.isEmpty) return NeuraRoomAttention.open;
    return _byRoomId[id] ?? NeuraRoomAttention.open;
  }

  /// The more protective of [a] and [b].
  static NeuraRoomAttention stricter(
    NeuraRoomAttention a,
    NeuraRoomAttention b,
  ) =>
      a.index >= b.index ? a : b;

  /// The attention that applies in [roomId]: the stricter of the built-in
  /// table and the user's own choice. A user choice can never loosen a
  /// built-in calm or private room.
  static NeuraRoomAttention effectiveFor(
    String? roomId, {
    Map<String, NeuraRoomAttention> userChoices = const {},
  }) {
    final builtIn = forRoom(roomId);
    final id = roomId?.trim();
    if (id == null || id.isEmpty) return builtIn;
    return stricter(builtIn, userChoices[id] ?? NeuraRoomAttention.open);
  }

  /// Returns the reason a candidate must stay silent in [roomId], or null when
  /// the room permits it. [userChoices] are the user's per-room settings,
  /// applied through [effectiveFor] so they can only tighten.
  static String? suppressionReason({
    required String? roomId,
    required double urgency,
    required double disruption,
    Map<String, NeuraRoomAttention> userChoices = const {},
  }) {
    if (urgency >= urgentOverride) return null;
    final attention = effectiveFor(roomId, userChoices: userChoices);
    final chosenByUser = attention != forRoom(roomId);
    switch (attention) {
      case NeuraRoomAttention.open:
        return null;
      case NeuraRoomAttention.calm:
        if (disruption <= calmMaxDisruption) return null;
        return chosenByUser
            ? 'Attention Guardian kept a disruptive suggestion out of a room '
                'you marked calm.'
            : 'Attention Guardian kept a disruptive suggestion out of a '
                'grounding room.';
      case NeuraRoomAttention.private:
        return chosenByUser
            ? 'Attention Guardian keeps proactive suggestions silent in a '
                'room you marked private.'
            : 'Attention Guardian keeps proactive suggestions silent in a '
                'private room.';
    }
  }
}
