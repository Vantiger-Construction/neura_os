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
    });
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
}
