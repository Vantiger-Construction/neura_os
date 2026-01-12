import '../behavior/neura_room.dart';

class NeuraObject {
  final String id;
  final String label;
  final NeuraRoom room;
  final String behaviorHint;

  const NeuraObject({
    required this.id,
    required this.label,
    required this.room,
    required this.behaviorHint,
  });
}
