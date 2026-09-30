import 'package:flutter/widgets.dart';

import 'neura_room.dart';

/// A content-free description of how Neura belongs in a room.
///
/// Profiles contain presentation and navigation hints only. They never carry
/// prompts, journal text, memories, transcripts, or cloud authority.
enum NeuraRoomStance {
  welcoming,
  reflective,
  playful,
  grounding,
  dreaming,
  guardian,
}

@immutable
class NeuraRoomPresenceProfile {
  const NeuraRoomPresenceProfile({
    required this.roomId,
    required this.cue,
    required this.stance,
    required this.alignment,
    required this.avatarScale,
    required this.activityCommandIds,
  });

  final String roomId;
  final String cue;
  final NeuraRoomStance stance;
  final Alignment alignment;
  final double avatarScale;
  final List<String> activityCommandIds;

  String get stanceLabel => switch (stance) {
        NeuraRoomStance.welcoming => 'Welcoming',
        NeuraRoomStance.reflective => 'Reflective',
        NeuraRoomStance.playful => 'Playful',
        NeuraRoomStance.grounding => 'Grounding',
        NeuraRoomStance.dreaming => 'Dreaming',
        NeuraRoomStance.guardian => 'Guardian',
      };

  static const Map<String, NeuraRoomPresenceProfile> _profiles = {
    'penthouse': NeuraRoomPresenceProfile(
      roomId: 'penthouse',
      cue: 'Ready to plan, talk, or move somewhere quieter.',
      stance: NeuraRoomStance.welcoming,
      alignment: Alignment.bottomCenter,
      avatarScale: 1,
      activityCommandIds: <String>['talk', 'rooms', 'intelligence'],
    ),
    'reflection_bay': NeuraRoomPresenceProfile(
      roomId: 'reflection_bay',
      cue: 'A slower place for reflection and private writing.',
      stance: NeuraRoomStance.reflective,
      alignment: Alignment.bottomLeft,
      avatarScale: 0.96,
      activityCommandIds: <String>[
        'journal-prompt',
        'voice-journal',
        'weekly-review',
      ],
    ),
    'joy_lounge': NeuraRoomPresenceProfile(
      roomId: 'joy_lounge',
      cue: 'A lighter room for humor, kindness, and momentum.',
      stance: NeuraRoomStance.playful,
      alignment: Alignment.bottomRight,
      avatarScale: 1.04,
      activityCommandIds: <String>['jokes', 'pay-it-forward', 'quests'],
    ),
    'mood_den': NeuraRoomPresenceProfile(
      roomId: 'mood_den',
      cue: 'A steady room for feelings, care, and grounding.',
      stance: NeuraRoomStance.grounding,
      alignment: Alignment.bottomCenter,
      avatarScale: 1,
      activityCommandIds: <String>[
        'mood-check-in',
        'care-loop',
        'therapy-journal',
      ],
    ),
    'dream_atrium': NeuraRoomPresenceProfile(
      roomId: 'dream_atrium',
      cue: 'A spacious room for dreams and imagination.',
      stance: NeuraRoomStance.dreaming,
      alignment: Alignment.bottomLeft,
      avatarScale: 0.98,
      activityCommandIds: <String>['dreams', 'journal-prompt'],
    ),
    'legacy_vault': NeuraRoomPresenceProfile(
      roomId: 'legacy_vault',
      cue: 'A protected room for memory, meaning, and future-you.',
      stance: NeuraRoomStance.guardian,
      alignment: Alignment.bottomRight,
      avatarScale: 1.02,
      activityCommandIds: <String>['legacy', 'timeline', 'memory-vault'],
    ),
  };

  static NeuraRoomPresenceProfile forRoom(NeuraRoom room) =>
      _profiles[room.id] ?? _profiles[NeuraRoom.penthouse.id]!;

  @visibleForTesting
  static Iterable<String> get profiledRoomIds => _profiles.keys;
}
