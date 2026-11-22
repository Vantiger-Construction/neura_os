import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/neura_shell/neura_room_mover.dart';

void main() {
  late NeuraRoom room;
  late bool safeMode;
  late List<String> moves;
  late NeuraRoomMover mover;

  setUp(() {
    room = NeuraRoom.penthouse;
    safeMode = false;
    moves = <String>[];
    mover = NeuraRoomMover(
      currentRoom: () => room,
      setRoom: (next) async {
        moves.add(next.id);
        room = next;
      },
      safeMode: () => safeMode,
    );
  });

  test('she moves only after the reply that asked has finished', () async {
    expect(mover.request('mood_den', owner: 'reply-1'), isTrue);
    expect(moves, isEmpty);
    expect(mover.pending?.id, 'mood_den');

    final move = await mover.settle('reply-1');
    expect(moves, <String>['mood_den']);
    expect(move?.from.id, 'penthouse');
    expect(move?.to.id, 'mood_den');
    expect(mover.pending, isNull);
  });

  test('another reply cannot settle or drop the move', () async {
    mover.request('joy_lounge', owner: 'reply-1');
    expect(await mover.settle('reply-2'), isNull);
    mover.drop('reply-2');
    expect(mover.pending?.id, 'joy_lounge');
    expect((await mover.settle('reply-1'))?.to.id, 'joy_lounge');
  });

  test('a stopped or failed reply drops its move', () async {
    mover.request('dream_atrium', owner: 'reply-1');
    mover.drop('reply-1');
    expect(await mover.settle('reply-1'), isNull);
    expect(moves, isEmpty);
  });

  test('a later request replaces the earlier one', () async {
    mover.request('mood_den', owner: 'reply-1');
    mover.request('her_suite', owner: 'reply-1');
    expect((await mover.settle('reply-1'))?.to.id, 'her_suite');
    expect(moves, <String>['her_suite']);
  });

  test('unknown rooms are refused', () {
    expect(mover.request('basement', owner: 'reply-1'), isFalse);
    expect(mover.request('', owner: 'reply-1'), isFalse);
    expect(mover.pending, isNull);
  });

  test('asking for the current room is accepted without a move', () async {
    mover.request('mood_den', owner: 'reply-1');
    expect(mover.request('penthouse', owner: 'reply-1'), isTrue);
    expect(mover.pending, isNull);
    expect(await mover.settle('reply-1'), isNull);
    expect(moves, isEmpty);
  });

  test('no move is requested or made in Safe Mode', () async {
    safeMode = true;
    expect(mover.request('mood_den', owner: 'reply-1'), isFalse);

    safeMode = false;
    mover.request('mood_den', owner: 'reply-2');
    safeMode = true;
    expect(await mover.settle('reply-2'), isNull);
    expect(moves, isEmpty);
    expect(mover.pending, isNull);
  });

  test('an undo works only from the room she moved to', () async {
    mover.request('legacy_vault', owner: 'reply-1');
    final move = (await mover.settle('reply-1'))!;
    expect(await mover.undo(move), isTrue);
    expect(room.id, 'penthouse');
    expect(moves, <String>['legacy_vault', 'penthouse']);

    // Once she has gone somewhere else, an old undo does nothing.
    room = NeuraRoom.joyLounge;
    expect(await mover.undo(move), isFalse);
    expect(room.id, 'joy_lounge');
  });
}
