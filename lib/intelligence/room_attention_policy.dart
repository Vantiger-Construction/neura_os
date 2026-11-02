/// How much proactive attention a penthouse room tolerates.
///
/// Rooms are where Neura and the user *are*, so they are an attention signal
/// in their own right: a room meant for private writing should not be
/// interrupted by a cheerful quest suggestion just because the dashboard
/// happened to evaluate candidates there.
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

  static NeuraRoomAttention forRoom(String? roomId) {
    final id = roomId?.trim();
    if (id == null || id.isEmpty) return NeuraRoomAttention.open;
    return _byRoomId[id] ?? NeuraRoomAttention.open;
  }

  /// Returns the reason a candidate must stay silent in [roomId], or null when
  /// the room permits it.
  static String? suppressionReason({
    required String? roomId,
    required double urgency,
    required double disruption,
  }) {
    if (urgency >= urgentOverride) return null;
    switch (forRoom(roomId)) {
      case NeuraRoomAttention.open:
        return null;
      case NeuraRoomAttention.calm:
        if (disruption <= calmMaxDisruption) return null;
        return 'Attention Guardian kept a disruptive suggestion out of a '
            'grounding room.';
      case NeuraRoomAttention.private:
        return 'Attention Guardian keeps proactive suggestions silent in a '
            'private room.';
    }
  }
}
