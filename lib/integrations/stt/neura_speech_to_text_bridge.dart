// Optional bridge. Only import this file if you have `speech_to_text` in pubspec.yaml.

import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../neura_sources_hooks.dart';

/// Hooks speech_to_text status into NeuraEventBus.
///
/// Usage:
///   final speech = stt.SpeechToText();
///   final bridge = NeuraSpeechToTextBridge(speech);
///   await bridge.initialize();
///   await bridge.listen();
class NeuraSpeechToTextBridge {
  final stt.SpeechToText speech;

  NeuraSpeechToTextBridge(this.speech);

  Future<bool> initialize() async {
    return speech.initialize(
      onStatus: (status) {
        final s = status.toLowerCase();
        if (s.contains('listening')) {
          NeuraSourcesHooks.sttStart(hint: 'STT status=listening');
        } else if (s.contains('notlistening') || s.contains('done')) {
          NeuraSourcesHooks.sttStop();
        }
      },
      onError: (err) {
        NeuraSourcesHooks.sttStop();
        NeuraSourcesHooks.error(err, null, 'STT error');
      },
    );
  }

  Future<void> listen({stt.SpeechListenOptions? options}) async {
    NeuraSourcesHooks.sttStart(hint: 'STT listen()');

    await speech.listen(
      listenOptions: options,
      onResult: (res) {
        // Stop listening when final result lands.
        if (res.finalResult) {
          NeuraSourcesHooks.sttStop();
          // Tiny “alive” touch: blink when user finishes speaking.
          NeuraSourcesHooks.pulseBlink();
        }
      },
    );
  }

  Future<void> stop() async {
    try {
      await speech.stop();
    } finally {
      NeuraSourcesHooks.sttStop();
    }
  }
}
