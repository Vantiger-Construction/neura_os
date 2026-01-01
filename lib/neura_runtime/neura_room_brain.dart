import 'neura_bus.dart';

/// Lightweight "room personality" presets.
///
/// These values are intended to drive avatar expression + voice defaults.

enum NeuraVoiceMode { calm, upbeat, serious, multiverse }

class NeuraRoomProfile {
  final double joy; // 0..1
  final double concern; // 0..1
  final double gesture; // 0..1
  final double headTilt; // -1..1
  final NeuraVoiceMode defaultVoice;
  final String vibe;

  const NeuraRoomProfile({
    required this.joy,
    required this.concern,
    required this.gesture,
    required this.headTilt,
    required this.defaultVoice,
    required this.vibe,
  });
}

class NeuraRoomBrain {
  static const profiles = <NeuraRoomKey, NeuraRoomProfile>{
    NeuraRoomKey.penthouse: NeuraRoomProfile(
      joy: 0.25,
      concern: 0.05,
      gesture: 0.25,
      headTilt: 0.05,
      defaultVoice: NeuraVoiceMode.upbeat,
      vibe: 'Operator mode',
    ),
    NeuraRoomKey.reflectionBay: NeuraRoomProfile(
      joy: 0.12,
      concern: 0.18,
      gesture: 0.10,
      headTilt: -0.06,
      defaultVoice: NeuraVoiceMode.calm,
      vibe: 'Reflective',
    ),
    NeuraRoomKey.joyLounge: NeuraRoomProfile(
      joy: 0.45,
      concern: 0.02,
      gesture: 0.35,
      headTilt: 0.08,
      defaultVoice: NeuraVoiceMode.upbeat,
      vibe: 'Bright + playful',
    ),
    NeuraRoomKey.moodDen: NeuraRoomProfile(
      joy: 0.10,
      concern: 0.30,
      gesture: 0.12,
      headTilt: -0.10,
      defaultVoice: NeuraVoiceMode.calm,
      vibe: 'Soft + grounded',
    ),
    NeuraRoomKey.dreamAtrium: NeuraRoomProfile(
      joy: 0.15,
      concern: 0.10,
      gesture: 0.08,
      headTilt: 0.12,
      defaultVoice: NeuraVoiceMode.calm,
      vibe: 'Slow + dreamy',
    ),
    NeuraRoomKey.legacyVault: NeuraRoomProfile(
      joy: 0.05,
      concern: 0.35,
      gesture: 0.05,
      headTilt: -0.05,
      defaultVoice: NeuraVoiceMode.serious,
      vibe: 'Respectful',
    ),
    NeuraRoomKey.settings: NeuraRoomProfile(
      joy: 0.10,
      concern: 0.05,
      gesture: 0.10,
      headTilt: 0.00,
      defaultVoice: NeuraVoiceMode.calm,
      vibe: 'Quiet helper',
    ),
  };

  static NeuraRoomProfile get(NeuraRoomKey room) => profiles[room] ?? profiles[NeuraRoomKey.penthouse]!;
}

/// Maps voice modes to your bundled offline WAV assets.
class NeuraVoiceProfile {
  static String pick(NeuraVoiceMode mode) {
    switch (mode) {
      case NeuraVoiceMode.upbeat:
        return 'Recording_upbeat.wav';
      case NeuraVoiceMode.serious:
        return 'to_tigger_vxxx2.wav';
      case NeuraVoiceMode.multiverse:
        return 'to_tigger_vxxx3.wav';
      case NeuraVoiceMode.calm:
      default:
        return 'Recording.wav';
    }
  }
}
