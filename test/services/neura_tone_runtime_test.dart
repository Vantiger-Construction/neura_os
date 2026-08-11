import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/neura_event_bus.dart';
import 'package:neuro_companion/core/neura_events.dart';
import 'package:neuro_companion/services/neura_tone_runtime.dart';

void main() {
  test('valid tone updates runtime and emits avatar mood event', () async {
    final event = Completer<NeuraMoodEvent>();
    final unsubscribe = NeuraEventBus.I.on<NeuraMoodEvent>((value) {
      if (!event.isCompleted) event.complete(value);
    });
    addTearDown(unsubscribe);

    final applied = NeuraToneRuntime.instance.setTone('quiet_private');

    expect(applied, isTrue);
    expect(NeuraToneRuntime.instance.tone.value, 'quiet_private');
    final mood = await event.future;
    expect(mood.mood, inInclusiveRange(-1.0, 1.0));
    expect(mood.energy, inInclusiveRange(0.0, 1.0));
    expect(mood.energy, lessThan(0.3));
  });

  test('invalid tone is rejected', () {
    final before = NeuraToneRuntime.instance.tone.value;
    expect(NeuraToneRuntime.instance.setTone('not_a_tone'), isFalse);
    expect(NeuraToneRuntime.instance.tone.value, before);
  });
}
