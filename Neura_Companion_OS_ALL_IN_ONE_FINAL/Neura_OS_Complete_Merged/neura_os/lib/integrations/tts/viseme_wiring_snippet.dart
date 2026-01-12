// lib/integrations/tts/viseme_wiring_snippet.dart
//
// Copy/paste reference snippet.
// Not imported anywhere by default.

import 'package:flutter_tts/flutter_tts.dart';
import 'neura_flutter_tts_viseme_bridge.dart';
import '../../avatar/avatar_orchestrator_viseme_ext.dart';
import '../../avatar/avatar_globals.dart';
import '../../core/neura_event_bus.dart';

Future<void> wireVisemesExample(FlutterTts tts) async {
  // 1) Emit visemes from TTS progress:
  await NeuraFlutterTtsVisemeBridge.attach(tts);

  // 2) Drive the avatar from those events:
  final visemeWiring = AvatarVisemeWiring(
    controller: AvatarGlobals.controller,
    bus: NeuraEventBus.I,
  )..start();

  // Keep a reference to visemeWiring if you need to stop() later.
}
