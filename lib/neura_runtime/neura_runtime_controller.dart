import 'dart:async';

import '../services/neura_voice_pack.dart';
import 'neura_bus.dart';
import 'neura_memory_watcher.dart';
import 'neura_room_brain.dart';
import 'neura_room_memory.dart';

/// Boots Neura's cross-app runtime:
/// - starts memory watcher
/// - reacts to room enter with a short "return line"
/// - optionally triggers a short voice clip in each room (offline assets)
class NeuraRuntimeController {
  NeuraRuntimeController._();
  static final NeuraRuntimeController I = NeuraRuntimeController._();

  bool _started = false;
  StreamSubscription? _sub;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    await NeuraVoicePack.I.init(enableMic: true);
    await NeuraMemoryWatcher.I.start();

    _sub = NeuraBus.I.stream.listen((e) async {
      if (e.type == NeuraEventType.roomEnter) {
        final room = e.room ?? NeuraBus.I.currentRoom;
        await _onRoomEnter(room);
      }
      if (e.type == NeuraEventType.voiceRequest) {
        final mode = e.data['mode'] as String?;
        final file = _fileForMode(mode);
        if (file != null) {
          await NeuraVoicePack.I.playAsset(file);
        }
      }
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _onRoomEnter(NeuraRoomKey room) async {
    // Tiny "welcome back" line based on last memory in that room.
    final line = NeuraRoomMemory.I.composeReturnLine(room);
    if (line != null) {
      NeuraBus.I.emit(NeuraEvent(NeuraEventType.prompt, room: room, message: line));
    }

    // Optional: play the room's default voice clip *sometimes*.
    // This avoids the OS shouting at you every click.
    final now = DateTime.now();
    final shouldPlay = (now.second % 3 == 0); // cheap throttle, deterministic
    if (shouldPlay) {
      final profile = NeuraRoomBrain.get(room);
      final asset = NeuraVoiceProfile.pick(profile.defaultVoice);
      await NeuraVoicePack.I.playAsset(asset);
    }
  }

  String? _fileForMode(String? mode) {
    switch (mode) {
      case 'upbeat':
        return 'Recording_upbeat.wav';
      case 'calm':
        return 'Recording.wav';
      case 'serious':
        return 'to_tigger_vxxx2.wav';
      case 'multiverse':
        return 'to_tigger_vxxx3.wav';
      default:
        return null;
    }
  }
}
