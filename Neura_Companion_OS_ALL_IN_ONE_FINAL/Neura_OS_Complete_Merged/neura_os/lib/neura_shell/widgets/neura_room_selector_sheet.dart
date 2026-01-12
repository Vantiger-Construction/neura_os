import 'package:flutter/material.dart';

import '../models/neura_room.dart';
import '../neura_shell.dart';

class NeuraRoomSelectorSheet {
  static Future<void> open(BuildContext context) async {
    final state = NeuraShell.of(context);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      backgroundColor: Colors.black.withOpacity(0.6),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        final current = state.room;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose a room', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  for (final r in NeuraRoom.all)
                    _RoomTile(
                      room: r,
                      selected: r.id == current.id,
                      onTap: () {
                        state.setRoom(r);
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SwitchListTile(
                      value: state.ambientEnabled,
                      onChanged: (v) => state.setAmbientEnabled(v),
                      title: const Text('Ambient sound'),
                      subtitle: const Text('Soft background loop per room'),
                    ),
                  ),
                ],
              ),
              if (state.ambientEnabled)
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.volume_down),
                      Expanded(
                        child: Slider(
                          value: state.ambientVolume,
                          onChanged: (v) => state.setAmbientVolume(v),
                        ),
                      ),
                      const Icon(Icons.volume_up),
                    ],
                  ),
                ),
              SwitchListTile(
                value: state.autoRoomSync,
                onChanged: (v) => state.setAutoRoomSync(v),
                title: const Text('Auto-sync room to tabs'),
                subtitle: const Text('Neura changes rooms when you change tabs'),
              ),

              SwitchListTile(
                value: state.showAvatar,
                onChanged: (v) => state.setShowAvatar(v),
                title: const Text('Show Neura overlay'),
                subtitle: const Text('Little floating Neura head on every screen'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _RoomTile extends StatelessWidget {
  final NeuraRoom room;
  final bool selected;
  final VoidCallback onTap;

  const _RoomTile({
    required this.room,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: room.gradient,
          ),
          border: Border.all(
            color: selected ? Colors.white.withOpacity(0.8) : Colors.white.withOpacity(0.12),
            width: selected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(room.icon, size: 22),
              const Spacer(),
              Text(room.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                selected ? 'Active' : 'Tap to enter',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
