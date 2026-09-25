import 'package:flutter/foundation.dart';

import '../neura_shell/models/neura_room.dart';
import '../neura_shell/models/neura_room_presence_profile.dart';
import '../services/neura_companion_presence.dart';
import '../src/shell/shell_prefs.dart';

/// Versioned, content-free state for an external avatar renderer.
///
/// A Unity host, Rive renderer, mascot window, or future native scene may
/// consume this contract without receiving conversation, memory, journal, or
/// credential data. It is presentation state only and grants no authority.
@immutable
class NeuraAvatarRuntimeSnapshot {
  const NeuraAvatarRuntimeSnapshot({
    required this.roomId,
    required this.phase,
    required this.stance,
    required this.motion,
    required this.scale,
    required this.safeMode,
  });

  static const int contractVersion = 1;

  final String roomId;
  final NeuraPresencePhase phase;
  final NeuraRoomStance stance;
  final NeuraCompanionMotion motion;
  final NeuraCompanionScale scale;
  final bool safeMode;

  Map<String, Object> toJson() => <String, Object>{
        'v': contractVersion,
        'room_id': roomId,
        'phase': phase.name,
        'stance': stance.name,
        'motion': motion.name,
        'scale': scale.name,
        'safe_mode': safeMode,
      };

  @override
  bool operator ==(Object other) =>
      other is NeuraAvatarRuntimeSnapshot &&
      roomId == other.roomId &&
      phase == other.phase &&
      stance == other.stance &&
      motion == other.motion &&
      scale == other.scale &&
      safeMode == other.safeMode;

  @override
  int get hashCode =>
      Object.hash(roomId, phase, stance, motion, scale, safeMode);
}

/// Publishes the latest avatar state to in-process renderers.
///
/// Publishing is idempotent, which makes it safe to call from lifecycle and
/// navigation listeners. External engines should subscribe to [snapshot] and
/// serialize [NeuraAvatarRuntimeSnapshot.toJson] over their own local bridge.
class NeuraAvatarRuntimeBridge {
  NeuraAvatarRuntimeBridge._();

  static final NeuraAvatarRuntimeBridge instance = NeuraAvatarRuntimeBridge._();

  final ValueNotifier<NeuraAvatarRuntimeSnapshot?> snapshot =
      ValueNotifier<NeuraAvatarRuntimeSnapshot?>(null);

  void publish({
    required NeuraRoom room,
    required NeuraPresencePhase phase,
    required ShellPrefs preferences,
  }) {
    final profile = NeuraRoomPresenceProfile.forRoom(room);
    final next = NeuraAvatarRuntimeSnapshot(
      roomId: room.id,
      phase: phase,
      stance: profile.stance,
      motion: phase == NeuraPresencePhase.safeMode
          ? NeuraCompanionMotion.still
          : preferences.companionMotion,
      scale: preferences.companionScale,
      safeMode: phase == NeuraPresencePhase.safeMode,
    );
    if (snapshot.value != next) snapshot.value = next;
  }

  @visibleForTesting
  void reset() => snapshot.value = null;
}
