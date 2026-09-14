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
      expect(
        chunker.extractReadyChunk('u1', 'Hello there.'),
        'Hello there.',
      );
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

    test('tracks multiple concurrent utterance ids independently', () {
      final chunker = SpeechStreamChunker();
      expect(chunker.extractReadyChunk('u1', 'Reply one.'), 'Reply one.');
      expect(chunker.extractReadyChunk('u2', 'Reply two.'), 'Reply two.');
      expect(
        chunker.extractReadyChunk('u1', 'Reply one. More one.'),
        'More one.',
      );
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
