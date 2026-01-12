import 'dart:async';

import 'package:flutter/material.dart';

import 'neura_bus.dart';
import 'neura_memory_watcher.dart';
import 'neura_room_memory.dart';

/// A top‑level widget that wraps the entire app and wires up Neura OS features.
///
/// This overlay is responsible for:
/// - Starting the [NeuraMemoryWatcher] which persists contextual memories.
/// - Listening to [NeuraBus] events to update per‑room cues.
/// - Displaying short return messages when entering rooms.
///
/// It does not directly render the Neura avatar; that is left to modules that
/// might integrate Rive or other animation systems. It only displays a
/// minimal message overlay at the bottom of the screen when needed.
class NeuraGlobalOverlay extends StatefulWidget {
  final Widget child;
  const NeuraGlobalOverlay({super.key, required this.child});

  @override
  State<NeuraGlobalOverlay> createState() => _NeuraGlobalOverlayState();
}

class _NeuraGlobalOverlayState extends State<NeuraGlobalOverlay> {
  StreamSubscription? _sub;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Start memory watcher once.
    NeuraMemoryWatcher.instance.start();
    // Listen for room enter events to show return lines.
    _sub = NeuraBus.instance.stream.listen((event) {
      if (event.type == NeuraEventType.roomEnter) {
        final room = event.room ?? NeuraBus.instance.currentRoom;
        final line = NeuraRoomMemory.instance.composeReturnLine(room);
        if (line != null) {
          setState(() {
            _message = line;
          });
          // Clear after a few seconds
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) {
              setState(() {
                _message = null;
              });
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_message != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Material(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  _message!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
