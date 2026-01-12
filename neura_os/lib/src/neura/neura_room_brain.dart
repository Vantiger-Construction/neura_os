import 'neura_bus.dart';

/// Personality profile describing Neura's tone and gestures in a room.
///
/// Each profile expresses a few simple numeric parameters such as joy,
/// concern and gesture which can be used by animation or voice layers to
/// adjust Neura's behaviour in a contextually appropriate way.
class NeuraRoomProfile {
  final double joy;
  final double concern;
  final double gesture;
  final double headTilt;
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

/// Available voice modes for the default voice selection.
///
/// These correspond to high level emotional tones. Only a subset are used in
/// the core OS; app specific modules may define additional values.
enum NeuraVoiceMode { calm, upbeat, serious, multiverse }

/// Central registry of profiles keyed by [NeuraRoom].
///
/// When a room is entered via [NeuraBus.enterRoom], the corresponding profile
/// can be consulted to choose animation and audio defaults.
class NeuraRoomBrain {
  static const Map<NeuraRoom, NeuraRoomProfile> profiles = {
    NeuraRoom.dashboard: NeuraRoomProfile(
      joy: 0.25,
      concern: 0.05,
      gesture: 0.25,
      headTilt: 0.05,
      defaultVoice: NeuraVoiceMode.upbeat,
      vibe: 'Operator mode',
    ),
    NeuraRoom.moodDen: NeuraRoomProfile(
      joy: 0.10,
      concern: 0.30,
      gesture: 0.12,
      headTilt: -0.10,
      defaultVoice: NeuraVoiceMode.calm,
      vibe: 'Soft + grounded',
    ),
    NeuraRoom.dreamBay: NeuraRoomProfile(
      joy: 0.15,
      concern: 0.10,
      gesture: 0.08,
      headTilt: 0.12,
      defaultVoice: NeuraVoiceMode.calm,
      vibe: 'Slow + dreamy',
    ),
    NeuraRoom.reflectionBay: NeuraRoomProfile(
      joy: 0.12,
      concern: 0.18,
      gesture: 0.08,
      headTilt: -0.06,
      defaultVoice: NeuraVoiceMode.calm,
      vibe: 'Reflective',
    ),
    NeuraRoom.joyLounge: NeuraRoomProfile(
      joy: 0.45,
      concern: 0.02,
      gesture: 0.35,
      headTilt: 0.08,
      defaultVoice: NeuraVoiceMode.upbeat,
      vibe: 'Bright + playful',
    ),
    NeuraRoom.legacyVault: NeuraRoomProfile(
      joy: 0.05,
      concern: 0.35,
      gesture: 0.05,
      headTilt: -0.05,
      defaultVoice: NeuraVoiceMode.serious,
      vibe: 'Respectful + calm',
    ),
    NeuraRoom.settings: NeuraRoomProfile(
      joy: 0.10,
      concern: 0.05,
      gesture: 0.10,
      headTilt: 0.00,
      defaultVoice: NeuraVoiceMode.calm,
      vibe: 'Quiet helper',
    ),
  };

  static NeuraRoomProfile get(NeuraRoom room) =>
      profiles[room] ?? profiles[NeuraRoom.dashboard]!;
}
