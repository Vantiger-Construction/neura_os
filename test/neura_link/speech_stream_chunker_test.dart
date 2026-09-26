import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/neura_link/speech_stream_chunker.dart';

void main() {
  group('SpeechStreamChunker.extractReadyChunk', () {
    test('returns nothing until a sentence boundary is reached', () {
      final chunker = SpeechStreamChunker();
      expect(chunker.extractReadyChunk('u1', 'Hello there'), isEmpty);
      expect(chunker.extractReadyChunk('u1', 'Hello there, how'), isEmpty);
    });

    test('returns exactly the newly-completed sentence', () {
      final chunker = SpeechStreamChunker();
      expect(chunker.extractReadyChunk('u1', 'Hello there.'), 'Hello there.');
      // Advancing further text without a new boundary yields nothing yet.
      expect(chunker.extractReadyChunk('u1', 'Hello there. And then'), isEmpty);
      // A second sentence completing returns only the new part.
      expect(
        chunker.extractReadyChunk('u1', 'Hello there. And then more!'),
        'And then more!',
      );
    });

    test('treats ?, !, and newline as sentence boundaries', () {
      final chunker = SpeechStreamChunker();
      expect(chunker.extractReadyChunk('u1', 'Really?'), 'Really?');
      expect(chunker.extractReadyChunk('u1', 'Really? Wow!'), 'Wow!');
      expect(chunker.extractReadyChunk('u1', 'Really? Wow!\n'), '');
    });

    test('an incomplete final clause is held back, not spoken early', () {
      final chunker = SpeechStreamChunker();
      chunker.extractReadyChunk('u1', 'First sentence.');
      expect(
        chunker.extractReadyChunk('u1', 'First sentence. Second, unfinished'),
        isEmpty,
      );
    });

    test('releases a long completed clause before the sentence ends', () {
      final chunker = SpeechStreamChunker(earlyClauseCharacters: 60);
      const first =
          'I can help you make this smaller by choosing one clear goal, ';
      expect(chunker.extractReadyChunk('u1', first), first.trim());
      expect(
        chunker.extractReadyChunk(
          'u1',
          '${first}then we can choose the first ten-minute step.',
        ),
        'then we can choose the first ten-minute step.',
      );
    });

    test('does not split long text without safe punctuation', () {
      final chunker = SpeechStreamChunker(earlyClauseCharacters: 20);
      const text = 'This is deliberately long but has no safe pause yet';
      expect(chunker.extractReadyChunk('u1', text), isEmpty);
      expect(chunker.finish('u1', text), text);
    });

    test('can disable early clauses while preserving sentence chunks', () {
      final chunker = SpeechStreamChunker(earlyClauseCharacters: 0);
      const clause =
          'This clause is long enough for normal early playback, but continues';
      expect(chunker.extractReadyChunk('u1', clause), isEmpty);
      expect(chunker.extractReadyChunk('u1', '$clause.'), '$clause.');
    });

    test('tracks multiple concurrent utterance ids independently', () {
      final chunker = SpeechStreamChunker();
      expect(chunker.extractReadyChunk('u1', 'Reply one.'), 'Reply one.');
      expect(chunker.extractReadyChunk('u2', 'Reply two.'), 'Reply two.');
      expect(
        chunker.extractReadyChunk('u1', 'Reply one. More one.'),
        'More one.',
      );
    });

    test('fragmented growing text matches a full-scan reference', () {
      final sentences = List.filled(
        100,
        'A long clause with é and 🌱. Next?\n',
      ).join();
      final text = '${sentences}Final unfinished clause';
      for (final step in [1, 2, 7, 61]) {
        final chunker = SpeechStreamChunker();
        var spoken = 0;
        for (var end = step; end < text.length; end += step) {
          final prefix = text.substring(0, end);
          var boundary = spoken;
          for (var i = spoken; i < prefix.length; i++) {
            if ('.!?\n'.contains(prefix[i])) boundary = i + 1;
          }
          final expected = prefix.substring(spoken, boundary).trim();
          expect(chunker.extractReadyChunk('reply', prefix), expected);
          spoken = boundary;
        }
        expect(chunker.finish('reply', text), text.substring(spoken).trim());
      }
    });

    test('finish and discard clear the cursor for an unfinished sentence', () {
      final chunker = SpeechStreamChunker();
      final long = List.filled(1000, 'word ').join();
      expect(chunker.extractReadyChunk('first', long), isEmpty);
      expect(chunker.finish('first', long), long.trim());
      expect(chunker.extractReadyChunk('first', 'Short!'), 'Short!');
      expect(chunker.extractReadyChunk('second', long), isEmpty);
      chunker.discard('second');
      expect(chunker.extractReadyChunk('second', 'Short?'), 'Short?');
    });
  });

  group('SpeechStreamChunker.finish', () {
    test('returns the unspoken trailing text and stops tracking it', () {
      final chunker = SpeechStreamChunker();
      chunker.extractReadyChunk('u1', 'First sentence.');
      expect(
        chunker.finish('u1', 'First sentence. Trailing clause'),
        'Trailing clause',
      );
      // The id is no longer tracked, so a fresh utterance starts from zero.
      expect(chunker.extractReadyChunk('u1', 'New reply.'), 'New reply.');
    });

    test('returns everything when nothing was spoken yet', () {
      final chunker = SpeechStreamChunker();
      expect(chunker.finish('u1', 'Only sentence.'), 'Only sentence.');
    });

    test('returns empty when the whole text was already spoken', () {
      final chunker = SpeechStreamChunker();
      chunker.extractReadyChunk('u1', 'Complete sentence.');
      expect(chunker.finish('u1', 'Complete sentence.'), isEmpty);
    });
  });

  group('SpeechStreamChunker.discard', () {
    test('drops tracking without returning the remainder', () {
      final chunker = SpeechStreamChunker();
      chunker.extractReadyChunk('u1', 'First sentence.');
      chunker.discard('u1');
      // A fresh utterance with the same id starts from zero again.
      expect(chunker.extractReadyChunk('u1', 'New reply.'), 'New reply.');
    });

    test('is a no-op for an id that was never tracked', () {
      final chunker = SpeechStreamChunker();
      expect(() => chunker.discard('unknown'), returnsNormally);
    });
  });
}
