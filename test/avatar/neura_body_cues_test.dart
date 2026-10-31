import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/motion/neura_body_cues.dart';
import 'package:neuro_companion/avatar/motion/neura_gesture.dart';
import 'package:neuro_companion/core/neura_event_bus.dart';
import 'package:neuro_companion/core/neura_events.dart';
import 'package:neuro_companion/neura_link/neura_tone.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('NeuraGesture.fromWire', () {
    test('accepts allow-listed names in either case style', () {
      expect(NeuraGesture.fromWire('nod'), NeuraGesture.nod);
      expect(NeuraGesture.fromWire('double_nod'), NeuraGesture.doubleNod);
      expect(NeuraGesture.fromWire('doubleNod'), NeuraGesture.doubleNod);
      expect(NeuraGesture.fromWire('TILT-LEFT'), NeuraGesture.tiltLeft);
    });

    test('rejects internal-only, unknown, oversized and non-string input', () {
      for (final bad in <Object?>[
        'glanceLeft',
        'shiftWeight',
        'stretch',
        'dance',
        'rm -rf /',
        '',
        'nod' * 20,
        null,
        42,
        <String, Object>{'gesture': 'nod'},
      ]) {
        expect(NeuraGesture.fromWire(bad), isNull, reason: '$bad');
      }
    });

    test('wire names round-trip', () {
      for (final g in NeuraGesture.wireAllowed) {
        expect(NeuraGesture.fromWire(g.wireName), g);
      }
    });
  });

  group('NeuraAvatarCueGate', () {
    late DateTime now;
    late NeuraAvatarCueGate gate;
    late List<NeuraEvent> seen;
    late void Function() unsub;

    setUp(() {
      now = DateTime(2026, 10, 27, 9);
      gate = NeuraAvatarCueGate(now: () => now);
      seen = [];
      final a = NeuraEventBus.I.on<NeuraGestureEvent>(seen.add);
      final b = NeuraEventBus.I.on<NeuraMoodEvent>(seen.add);
      unsub = () {
        a();
        b();
      };
    });
    tearDown(() => unsub());

    test('applies a valid gesture with clamped intensity', () async {
      expect(gate.apply({'gesture': 'bounce', 'intensity': 4}), isTrue);
      await _flush();
      final e = seen.single as NeuraGestureEvent;
      expect(e.gesture, NeuraGesture.bounce);
      expect(e.intensity, 1.0);
    });

    test('applies mood/energy alongside a gesture', () async {
      expect(
        gate.apply({'gesture': 'lean_in', 'mood': 0.5, 'energy': 0.2}),
        isTrue,
      );
      await _flush();
      expect(seen.whereType<NeuraMoodEvent>().single.mood, 0.5);
      expect(seen.whereType<NeuraGestureEvent>().single.gesture,
          NeuraGesture.leanIn);
    });

    test('rejects unknown keys, bad types and non-finite numbers', () async {
      expect(gate.apply({'gesture': 'nod', 'text': 'hello'}), isFalse);
      expect(gate.apply({'gesture': 'nod', 'intensity': 'max'}), isFalse);
      expect(gate.apply({'mood': double.nan}), isFalse);
      expect(gate.apply({'gesture': 'shiftWeight'}), isFalse);
      expect(gate.apply({}), isFalse);
      await _flush();
      expect(seen, isEmpty);
    });

    test('enforces spacing and a per-window budget', () {
      expect(gate.apply({'gesture': 'nod'}), isTrue);
      expect(gate.apply({'gesture': 'nod'}), isFalse, reason: 'too soon');
      var accepted = 1;
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(milliseconds: 400));
        if (gate.apply({'gesture': 'nod'})) accepted++;
      }
      expect(accepted, NeuraAvatarCueGate.maxPerWindow);
      now = now.add(const Duration(seconds: 6));
      expect(gate.apply({'gesture': 'nod'}), isTrue, reason: 'window reset');
    });
  });

  group('NeuraSpeechBeats', () {
    test('classifies sentences by punctuation only', () {
      List<NeuraSentenceKind> kinds(String t) =>
          NeuraSpeechBeats.analyze(t).map((b) => b.$2).toList();

      expect(kinds('Okay.'), [NeuraSentenceKind.opening]);
      expect(kinds('No way!'), [NeuraSentenceKind.exclamation]);
      expect(kinds('Sure. Why?'),
          [NeuraSentenceKind.opening, NeuraSentenceKind.question]);
      expect(
        kinds('Hey Steven! How did the build go today? I think we nailed it.'),
        [
          NeuraSentenceKind.exclamation,
          NeuraSentenceKind.statement,
          NeuraSentenceKind.question,
          NeuraSentenceKind.statement,
        ],
      );
      expect(kinds("Hmm... I'm not sure about that."),
          [NeuraSentenceKind.trailing, NeuraSentenceKind.statement]);
      expect(kinds(''), isEmpty);
    });

    test('beat offsets are ordered and inside the text', () {
      const text = 'First line. Second line? Third line! And the last one';
      final beats = NeuraSpeechBeats.analyze(text);
      for (var i = 0; i < beats.length; i++) {
        expect(beats[i].$1, inInclusiveRange(0, text.length));
        if (i > 0) expect(beats[i].$1, greaterThanOrEqualTo(beats[i - 1].$1));
      }
    });

    test('TTS progress fires the gesture for the sentence being spoken',
        () async {
      final beats = NeuraSpeechBeats(random: math.Random(1));
      final seen = <NeuraGestureEvent>[];
      final unsub = NeuraEventBus.I.on<NeuraGestureEvent>(seen.add);
      addTearDown(unsub);
      addTearDown(beats.end);

      beats.begin('Hello there. Is this working?');
      beats.progress(0);
      await _flush();
      expect(seen.single.gesture, NeuraGesture.nod);

      beats.progress(28); // near the end of the question
      await _flush();
      expect(seen.last.gesture,
          anyOf(NeuraGesture.tiltLeft, NeuraGesture.tiltRight));

      final count = seen.length;
      beats.progress(28); // same position again: no duplicate beat
      await _flush();
      expect(seen.length, count);
    });
  });

  test('every tone maps to an in-range mood and energy', () {
    for (final tone in NeuraTone.values) {
      final (mood, energy) = NeuraToneMotion.moodFor(tone);
      expect(mood, inInclusiveRange(-1, 1));
      expect(energy, inInclusiveRange(0, 1));
    }
  });
}
