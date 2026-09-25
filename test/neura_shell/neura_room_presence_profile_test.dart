import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/neura_shell/models/neura_room_presence_profile.dart';

void main() {
  test('every built-in room has a presence profile and local activities', () {
    expect(
      NeuraRoomPresenceProfile.profiledRoomIds.toSet(),
      NeuraRoom.all.map((room) => room.id).toSet(),
    );
    for (final room in NeuraRoom.all) {
      final profile = NeuraRoomPresenceProfile.forRoom(room);
      expect(profile.roomId, room.id);
      expect(profile.cue, isNotEmpty);
      expect(profile.activityCommandIds, isNotEmpty);
    }
  });

  test('unknown rooms fall back to the Penthouse profile', () {
    const unknown = NeuraRoom(
      id: 'future_room',
      title: 'Future Room',
      icon: Icons.circle,
      gradient: <Color>[Colors.black, Colors.white],
    );
    expect(
      NeuraRoomPresenceProfile.forRoom(unknown).roomId,
      NeuraRoom.penthouse.id,
    );
  });
}
