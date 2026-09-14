/// Splits a growing, streamed reply into speakable sentence chunks.
///
/// Kept deliberately free of any TTS or audio dependency so the chunking
/// rule itself -- the part most worth getting right -- can be unit tested
/// without a native speech engine. One instance tracks a "spoken up to"
/// cursor per utterance id, since several replies can stream concurrently.
class SpeechStreamChunker {
  final Map<String, int> _spokenUpTo = {};

  /// Returns any newly-completed sentence(s) from the unspoken tail of
  /// [fullText] for utterance [id], advancing the internal cursor past them.
  /// Returns an empty string when no full sentence has completed yet.
  String extractReadyChunk(String id, String fullText) {
    final start = _spokenUpTo[id] ?? 0;
    if (start >= fullText.length) return '';
    final unspoken = fullText.substring(start);
    final boundary = _lastSentenceBoundary(unspoken);
    if (boundary <= 0) return '';
    _spokenUpTo[id] = start + boundary;
    return unspoken.substring(0, boundary).trim();
  }

  /// Returns the remaining unspoken tail of [fullText] for [id] and stops
  /// tracking it. Use only once an utterance is known to be complete (a
  /// final, non-streaming reply) -- never after an interruption.
  String finish(String id, String fullText) {
    final start = _spokenUpTo.remove(id) ?? 0;
    if (start >= fullText.length) return '';
    return fullText.substring(start).trim();
  }

  /// Stops tracking [id] without returning its unspoken tail. Use for
  /// barge-in / interruption, where the remainder must never be spoken.
  void discard(String id) => _spokenUpTo.remove(id);

  /// Index just past the last sentence-ending punctuation in [text], or -1
  /// when no sentence has completed yet.
  static int _lastSentenceBoundary(String text) {
    var last = -1;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '.' || char == '!' || char == '?' || char == '\n') {
        last = i + 1;
      }
    }
    return last;
  }
}
