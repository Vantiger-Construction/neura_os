// Optional bridge. Only import this file if you have `flutter_tts` in pubspec.yaml.

import 'package:flutter_tts/flutter_tts.dart';

import '../neura_sources_hooks.dart';

/// Hooks FlutterTts lifecycle into NeuraEventBus.
///
/// Usage:
///   final tts = FlutterTts();
///   await NeuraFlutterTtsBridge(tts).attach();
class NeuraFlutterTtsBridge {
  final FlutterTts tts;
  NeuraFlutterTtsBridge(this.tts);

  Future<void> attach() async {
    tts.setStartHandler(() {
      NeuraSourcesHooks.ttsStart(hint: 'flutter_tts start');
    });

    tts.setCompletionHandler(() {
      NeuraSourcesHooks.ttsStop();
    });

    tts.setCancelHandler(() {
      NeuraSourcesHooks.ttsStop();
    });

    tts.setPauseHandler(() {
      NeuraSourcesHooks.ttsStop();
    });

    tts.setContinueHandler(() {
      NeuraSourcesHooks.ttsStart(hint: 'flutter_tts continue');
    });

    tts.setErrorHandler((msg) {
      NeuraSourcesHooks.ttsStop();
      NeuraSourcesHooks.error(msg, null, 'TTS error');
    });
  }
}
