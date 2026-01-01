import 'package:flutter/material.dart';

import '../neura_runtime/neura_bus.dart';
import '../neura_runtime/neura_room_memory.dart';

class NeuraTimelineScreen extends StatefulWidget {
  const NeuraTimelineScreen({super.key});

  @override
  State<NeuraTimelineScreen> createState() => _NeuraTimelineScreenState();
}

class _NeuraTimelineScreenState extends State<NeuraTimelineScreen> {
  @override
  void initState() {
    super.initState();
    // Ensure memory is hydrated.
    NeuraRoomMemory.I.load();
  }

  String _roomLabel(NeuraRoomKey? r) => (r ?? NeuraBus.I.currentRoom).name;

  @override
  Widget build(BuildContext context) {
    final log = NeuraBus.I.log.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neura Timeline'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            onPressed: () => setState(() => NeuraBus.I.log.clear()),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: log.length,
        itemBuilder: (context, i) {
          final e = log[i];
          return Card(
            child: ListTile(
              leading: Icon(_iconFor(e.type)),
              title: Text(e.message ?? e.type.name),
              subtitle: Text('${_roomLabel(e.room)} • ${e.data.isEmpty ? '' : e.data}'),
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(NeuraEventType t) {
    switch (t) {
      case NeuraEventType.roomEnter:
        return Icons.door_front_door_outlined;
      case NeuraEventType.roomExit:
        return Icons.logout;
      case NeuraEventType.error:
        return Icons.error_outline;
      case NeuraEventType.success:
        return Icons.check_circle_outline;
      case NeuraEventType.prompt:
        return Icons.tips_and_updates_outlined;
      case NeuraEventType.voiceRequest:
        return Icons.record_voice_over_outlined;
      case NeuraEventType.userTypingStart:
        return Icons.edit;
      case NeuraEventType.userTypingStop:
        return Icons.edit_off;
      case NeuraEventType.userIdle:
        return Icons.self_improvement;
      case NeuraEventType.userActive:
        return Icons.bolt;
    }
  }
}
