import 'package:flutter/foundation.dart';

import '../neura_shell/models/neura_room.dart';
import '../neura_shell/models/neura_room_presence_profile.dart';
import '../services/neura_companion_presence.dart';
import '../src/shell/shell_prefs.dart';

/// Lighting the renderer applies to the room. [standard] is the room's own
/// look; the named moods are offered in Her Suite.
enum NeuraStageLighting { standard, gold, aurora, dusk }

/// How the renderer frames Neura. Presentation only.
enum NeuraStageCamera { follow, wide, face }

/// What Neura is doing in the scene. [resting] is shown in Her Suite when the
/// user lets her rest; it never changes microphone, voice or suggestions.
enum NeuraCompanionActivity { present, resting }

/// Display-only stage choices from the Flutter UI (Her Suite lighting, the
/// camera, letting her rest). Content-free, like the rest of the snapshot.
@immutable
class NeuraStagePresentation {
  const NeuraStagePresentation({
    this.lighting = NeuraStageLighting.standard,
    this.camera = NeuraStageCamera.follow,
    this.activity = NeuraCompanionActivity.present,
  });

  static const NeuraStagePresentation defaults = NeuraStagePresentation();

  final NeuraStageLighting lighting;
  final NeuraStageCamera camera;
  final NeuraCompanionActivity activity;

  NeuraStagePresentation copyWith({
    NeuraStageLighting? lighting,
    NeuraStageCamera? camera,
    NeuraCompanionActivity? activity,
  }) =>
      NeuraStagePresentation(
        lighting: lighting ?? this.lighting,
        camera: camera ?? this.camera,
        activity: activity ?? this.activity,
      );

  @override
  bool operator ==(Object other) =>
      other is NeuraStagePresentation &&
      lighting == other.lighting &&
      camera == other.camera &&
      activity == other.activity;

  @override
  int get hashCode => Object.hash(lighting, camera, activity);
}

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
    this.lighting = NeuraStageLighting.standard,
    this.camera = NeuraStageCamera.follow,
    this.activity = NeuraCompanionActivity.present,
  });

  /// v2 added `her_suite`, `lighting`, `camera` and `activity`. Receivers
  /// still accept v1, which can't name the new room or carry those fields.
  static const int contractVersion = 2;

  final String roomId;
  final NeuraPresencePhase phase;
  final NeuraRoomStance stance;
  final NeuraCompanionMotion motion;
  final NeuraCompanionScale scale;
  final bool safeMode;
  final NeuraStageLighting lighting;
  final NeuraStageCamera camera;
  final NeuraCompanionActivity activity;

  Map<String, Object> toJson() => <String, Object>{
        'v': contractVersion,
        'room_id': roomId,
        'phase': phase.name,
        'stance': stance.name,
        'motion': motion.name,
        'scale': scale.name,
        'safe_mode': safeMode,
        'lighting': lighting.name,
        'camera': camera.name,
        'activity': activity.name,
      };

  @override
  bool operator ==(Object other) =>
      other is NeuraAvatarRuntimeSnapshot &&
      roomId == other.roomId &&
      phase == other.phase &&
      stance == other.stance &&
      motion == other.motion &&
      scale == other.scale &&
      safeMode == other.safeMode &&
      lighting == other.lighting &&
      camera == other.camera &&
      activity == other.activity;

  @override
  int get hashCode => Object.hash(
        roomId,
        phase,
        stance,
        motion,
        scale,
        safeMode,
        lighting,
        camera,
        activity,
      );
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

  NeuraStagePresentation _stage = NeuraStagePresentation.defaults;
  ({NeuraRoom room, NeuraPresencePhase phase, ShellPrefs preferences})? _last;

  NeuraStagePresentation get stage => _stage;

  void publish({
    required NeuraRoom room,
    required NeuraPresencePhase phase,
    required ShellPrefs preferences,
  }) {
    _last = (room: room, phase: phase, preferences: preferences);
    final profile = NeuraRoomPresenceProfile.forRoom(room);
    final safe = phase == NeuraPresencePhase.safeMode;
    final next = NeuraAvatarRuntimeSnapshot(
      roomId: room.id,
      phase: phase,
      stance: profile.stance,
      motion: safe ? NeuraCompanionMotion.still : preferences.companionMotion,
      scale: preferences.companionScale,
      safeMode: safe,
      lighting: _stage.lighting,
      camera: _stage.camera,
      // Safe Mode always shows the standard, present pose. Resting belongs
      // to Her Suite; anywhere else she is present.
      activity: safe || room.id != NeuraRoom.herSuite.id
          ? NeuraCompanionActivity.present
          : _stage.activity,
    );
    if (snapshot.value != next) snapshot.value = next;
  }

  /// Updates the display-only stage choices and republishes the last room,
  /// phase and preferences with them. Before the first [publish], it only
  /// stores the choices.
  void updateStage(NeuraStagePresentation stage) {
    if (_stage == stage) return;
    _stage = stage;
    final last = _last;
    if (last != null) {
      publish(
        room: last.room,
        phase: last.phase,
        preferences: last.preferences,
      );
    }
  }

  @visibleForTesting
  void reset() {
    snapshot.value = null;
    _stage = NeuraStagePresentation.defaults;
    _last = null;
  }
}
