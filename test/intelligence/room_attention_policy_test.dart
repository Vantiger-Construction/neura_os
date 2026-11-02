import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/intelligence/room_attention_policy.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';

void main() {
  group('NeuraRoomAttentionPolicy.forRoom', () {
    test('classifies private, calm, and open rooms', () {
      expect(
        NeuraRoomAttentionPolicy.forRoom(NeuraRoom.reflectionBay.id),
        NeuraRoomAttention.private,
      );
      expect(
        NeuraRoomAttentionPolicy.forRoom(NeuraRoom.legacyVault.id),
        NeuraRoomAttention.private,
      );
      expect(
        NeuraRoomAttentionPolicy.forRoom(NeuraRoom.moodDen.id),
        NeuraRoomAttention.calm,
      );
      for (final room in [
        NeuraRoom.penthouse,
        NeuraRoom.joyLounge,
        NeuraRoom.dreamAtrium,
      ]) {
        expect(
          NeuraRoomAttentionPolicy.forRoom(room.id),
          NeuraRoomAttention.open,
          reason: room.id,
        );
      }
    });

    test('treats unknown, blank, and missing rooms as open', () {
      expect(
        NeuraRoomAttentionPolicy.forRoom(null),
        NeuraRoomAttention.open,
      );
      expect(NeuraRoomAttentionPolicy.forRoom('  '), NeuraRoomAttention.open);
      expect(
        NeuraRoomAttentionPolicy.forRoom('not_a_room'),
        NeuraRoomAttention.open,
      );
    });

    test('every listed room id is a real NeuraRoom', () {
      final realIds = NeuraRoom.all.map((room) => room.id).toSet();
      for (final id in ['reflection_bay', 'legacy_vault', 'mood_den']) {
        expect(realIds, contains(id));
      }
    });
  });

  group('NeuraRoomAttentionPolicy.suppressionReason', () {
    test('silences non-urgent candidates in a private room', () {
      final reason = NeuraRoomAttentionPolicy.suppressionReason(
        roomId: NeuraRoom.reflectionBay.id,
        urgency: 0.5,
        disruption: 0.1,
      );
      expect(reason, contains('private room'));
    });

    test('lets urgent candidates through a private room', () {
      expect(
        NeuraRoomAttentionPolicy.suppressionReason(
          roomId: NeuraRoom.legacyVault.id,
          urgency: NeuraRoomAttentionPolicy.urgentOverride,
          disruption: 0.9,
        ),
        isNull,
      );
    });

    test('a calm room only admits low-disruption candidates', () {
      expect(
        NeuraRoomAttentionPolicy.suppressionReason(
          roomId: NeuraRoom.moodDen.id,
          urgency: 0.5,
          disruption: NeuraRoomAttentionPolicy.calmMaxDisruption,
        ),
        isNull,
      );
      expect(
        NeuraRoomAttentionPolicy.suppressionReason(
          roomId: NeuraRoom.moodDen.id,
          urgency: 0.5,
          disruption: 0.6,
        ),
        contains('grounding room'),
      );
    });

    test('an open room never suppresses', () {
      expect(
        NeuraRoomAttentionPolicy.suppressionReason(
          roomId: NeuraRoom.penthouse.id,
          urgency: 0,
          disruption: 1,
        ),
        isNull,
      );
    });
  });
}
