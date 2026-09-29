import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';

void main() {
  test('resolves every built-in room from the indexed lookup', () {
    for (final room in NeuraRoom.all) {
      expect(NeuraRoom.fromId(room.id), same(room));
    }
  });

  test('unknown and absent room ids still fall back to the penthouse', () {
    expect(NeuraRoom.fromId(null), same(NeuraRoom.penthouse));
    expect(NeuraRoom.fromId('unknown'), same(NeuraRoom.penthouse));
  });
}
