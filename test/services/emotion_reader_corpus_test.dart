import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/emotion_analysis_service.dart';

import 'emotion_reader_corpus.dart';
import 'emotion_reader_emoji_holdout.dart';
import 'emotion_reader_holdout.dart';

class _Score {
  int correct = 0;
  int labelled = 0;
  final misses = <String>[];
  final falseCues = <String>[];
  double get accuracy => correct / labelled;

  @override
  String toString() => '$correct/$labelled correct '
      '(${(accuracy * 100).toStringAsFixed(0)}%), ${falseCues.length} false '
      'cues${misses.map((m) => '\n  MISS $m').join()}'
      '${falseCues.map((m) => '\n  FALSE $m').join()}';
}

_Score _score(List<(String, Object?)> set) {
  const reader = EmotionAnalysisService();
  final s = _Score();
  for (final (text, expected) in set) {
    final read = reader.read(text);
    if (expected == null) {
      if (read.promptCue.isNotEmpty || read.primary != null) {
        s.falseCues.add('"$text" -> $read');
      }
      continue;
    }
    s.labelled++;
    final ok = expected is List
        ? expected.contains(read.primary)
        : read.primary == expected;
    if (ok) {
      s.correct++;
    } else {
      s.misses.add('"$text" expected $expected, got $read');
    }
  }
  return s;
}

void main() {
  test('reader agrees with the tuning corpus and never cues neutral text', () {
    final s = _score(emotionReaderCorpus);
    // ignore: avoid_print
    print('tuning corpus: $s');
    // A wrong cue is worse than none, so neutral text must stay clean.
    expect(s.falseCues, isEmpty);
    expect(s.accuracy, greaterThanOrEqualTo(0.9));
  });

  test('reader generalizes to messages it was never tuned on', () {
    final s = _score(emotionReaderHoldout);
    // ignore: avoid_print
    print('held-out set: $s');
    expect(s.falseCues, isEmpty);
    expect(s.accuracy, greaterThanOrEqualTo(0.8));
  });

  test('reader understands emoji it was never tuned on', () {
    final s = _score(emotionReaderEmojiHoldout);
    // ignore: avoid_print
    print('emoji held-out set: $s');
    expect(s.falseCues, isEmpty);
    expect(s.accuracy, greaterThanOrEqualTo(0.8));
  });
}
