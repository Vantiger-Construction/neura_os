import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_companion_presence.dart';

void main() {
  test('Safe Mode overrides and invalidates local presence leases', () {
    final safeMode = ValueNotifier(false);
    final presence = NeuraCompanionPresence(safeMode: safeMode);
    addTearDown(() {
      presence.dispose();
      safeMode.dispose();
    });

    final speech = presence.acquireSpeaking();
    expect(speech, isNotNull);
    expect(presence.state.value.phase, NeuraPresencePhase.speaking);

    safeMode.value = true;
    expect(presence.state.value.phase, NeuraPresencePhase.safeMode);
    expect(presence.acquireListening(), isNull);

    safeMode.value = false;
    expect(presence.state.value.phase, NeuraPresencePhase.idle);

    speech!.release();
    expect(presence.state.value.phase, NeuraPresencePhase.idle);
  });

  test('listening has priority while overlapping local activity ends', () {
    final safeMode = ValueNotifier(false);
    final presence = NeuraCompanionPresence(safeMode: safeMode);
    addTearDown(() {
      presence.dispose();
      safeMode.dispose();
    });

    final thinking = presence.acquireThinking()!;
    final speaking = presence.acquireSpeaking()!;
    final listening = presence.acquireListening()!;

    expect(presence.state.value.phase, NeuraPresencePhase.listening);
    expect(presence.state.value.microphoneActive, isTrue);

    listening.release();
    expect(presence.state.value.phase, NeuraPresencePhase.speaking);
    expect(presence.state.value.voiceActive, isTrue);

    speaking.release();
    expect(presence.state.value.phase, NeuraPresencePhase.thinking);

    thinking.release();
    expect(presence.state.value.phase, NeuraPresencePhase.idle);
  });
}
