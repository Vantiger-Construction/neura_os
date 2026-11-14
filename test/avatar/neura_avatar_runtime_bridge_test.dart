import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/neura_avatar_runtime_bridge.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/services/neura_companion_presence.dart';
import 'package:neuro_companion/src/shell/shell_prefs.dart';

void main() {
  final bridge = NeuraAvatarRuntimeBridge.instance;

  tearDown(bridge.reset);

  test('publishes a versioned content-free room snapshot', () {
    bridge.publish(
      room: NeuraRoom.dreamAtrium,
      phase: NeuraPresencePhase.thinking,
      preferences: ShellPrefs.defaults.copyWith(
        companionMotion: NeuraCompanionMotion.expressive,
        companionScale: NeuraCompanionScale.large,
      ),
    );

    final json = bridge.snapshot.value!.toJson();
    expect(json['v'], NeuraAvatarRuntimeSnapshot.contractVersion);
    expect(json['room_id'], 'dream_atrium');
    expect(json['phase'], 'thinking');
    expect(json['motion'], 'expressive');
    expect(json.keys, <String>{
      'v',
      'room_id',
      'phase',
      'stance',
      'motion',
      'scale',
      'safe_mode',
      'lighting',
      'camera',
      'activity',
    });
    expect(json['lighting'], 'standard');
    expect(json['camera'], 'follow');
    expect(json['activity'], 'present');
    expect(json.toString(), isNot(contains('prompt')));
    expect(json.toString(), isNot(contains('memory')));
    expect(json.toString(), isNot(contains('transcript')));
  });

  test('Safe Mode forces a still avatar contract', () {
    bridge.publish(
      room: NeuraRoom.joyLounge,
      phase: NeuraPresencePhase.safeMode,
      preferences: ShellPrefs.defaults.copyWith(
        companionMotion: NeuraCompanionMotion.expressive,
      ),
    );
    expect(bridge.snapshot.value!.motion, NeuraCompanionMotion.still);
    expect(bridge.snapshot.value!.safeMode, isTrue);
  });

  test('stage choices republish the last room and phase', () {
    bridge.publish(
      room: NeuraRoom.herSuite,
      phase: NeuraPresencePhase.idle,
      preferences: ShellPrefs.defaults,
    );
    bridge.updateStage(
      const NeuraStagePresentation(
        lighting: NeuraStageLighting.aurora,
        camera: NeuraStageCamera.face,
        activity: NeuraCompanionActivity.resting,
      ),
    );
    final json = bridge.snapshot.value!.toJson();
    expect(json['room_id'], 'her_suite');
    expect(json['lighting'], 'aurora');
    expect(json['camera'], 'face');
    expect(json['activity'], 'resting');
  });

  test('stage choices made before the first publish are kept', () {
    bridge.updateStage(
      const NeuraStagePresentation(lighting: NeuraStageLighting.dusk),
    );
    expect(bridge.snapshot.value, isNull);
    bridge.publish(
      room: NeuraRoom.herSuite,
      phase: NeuraPresencePhase.idle,
      preferences: ShellPrefs.defaults,
    );
    expect(bridge.snapshot.value!.lighting, NeuraStageLighting.dusk);
  });

  test('she only rests in Her Suite, and never in Safe Mode', () {
    bridge.updateStage(
      const NeuraStagePresentation(activity: NeuraCompanionActivity.resting),
    );
    bridge.publish(
      room: NeuraRoom.penthouse,
      phase: NeuraPresencePhase.idle,
      preferences: ShellPrefs.defaults,
    );
    expect(bridge.snapshot.value!.activity, NeuraCompanionActivity.present);
    bridge.publish(
      room: NeuraRoom.herSuite,
      phase: NeuraPresencePhase.safeMode,
      preferences: ShellPrefs.defaults,
    );
    expect(bridge.snapshot.value!.activity, NeuraCompanionActivity.present);
    expect(bridge.snapshot.value!.motion, NeuraCompanionMotion.still);
    bridge.publish(
      room: NeuraRoom.herSuite,
      phase: NeuraPresencePhase.idle,
      preferences: ShellPrefs.defaults,
    );
    expect(bridge.snapshot.value!.activity, NeuraCompanionActivity.resting);
  });

  test('every v2 snapshot stays within the 512-character receiver limit', () {
    bridge.updateStage(
      const NeuraStagePresentation(
        lighting: NeuraStageLighting.aurora,
        camera: NeuraStageCamera.follow,
        activity: NeuraCompanionActivity.resting,
      ),
    );
    for (final room in NeuraRoom.all) {
      bridge.publish(
        room: room,
        phase: NeuraPresencePhase.listening,
        preferences: ShellPrefs.defaults.copyWith(
          companionMotion: NeuraCompanionMotion.expressive,
          companionScale: NeuraCompanionScale.standard,
        ),
      );
      final json = bridge.snapshot.value!.toJson();
      expect(json.toString().length, lessThan(512), reason: room.id);
    }
  });
}
