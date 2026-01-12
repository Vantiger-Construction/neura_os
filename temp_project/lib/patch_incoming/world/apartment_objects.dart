import 'neura_object.dart';
import '../behavior/neura_room.dart';

class ApartmentObjects {
  static final objects = <NeuraObject>[
    NeuraObject(
      id: 'desk',
      label: 'Journal Desk',
      room: NeuraRoom.journalDesk,
      behaviorHint: 'reflection',
    ),
    NeuraObject(
      id: 'window',
      label: 'Dream Window',
      room: NeuraRoom.dreamWindow,
      behaviorHint: 'dream',
    ),
    NeuraObject(
      id: 'couch',
      label: 'Calm Couch',
      room: NeuraRoom.calmLounge,
      behaviorHint: 'calm',
    ),
    NeuraObject(
      id: 'shelf',
      label: 'Memory Shelf',
      room: NeuraRoom.reflectionBay,
      behaviorHint: 'memory',
    ),
  ];
}
