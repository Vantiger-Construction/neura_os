/// Splits a growing, streamed reply into speakable sentence chunks.
///
/// Kept deliberately free of any TTS or audio dependency so the chunking
/// rule itself -- the part most worth getting right -- can be unit tested
/// without a native speech engine. One instance tracks a "spoken up to"
/// cursor per utterance id, since several replies can stream concurrently.
class SpeechStreamChunker {
  final Map<String, int> _spokenUpTo = {};
  final Map<String, int> _scannedUpTo = {};

  /// Returns any newly-completed sentence(s) from the unspoken tail of
  /// [fullText] for utterance [id], advancing the internal cursor past them.
  /// Returns an empty string when no full sentence has completed yet.
  String extractReadyChunk(String id, String fullText) {
    final start = _spokenUpTo[id] ?? 0;
    if (start >= fullText.length) return '';
    // Stream snapshots grow by appending deltas. An unfinished sentence has
    // already been scanned, so inspect only the newly appended characters.
    // A shorter snapshot falls back to scanning from the unspoken cursor.
    final scanned = _scannedUpTo[id] ?? start;
    final scanStart = scanned <= fullText.length ? scanned : start;
    final boundary = _lastSentenceBoundary(fullText, scanStart);
    _scannedUpTo[id] = fullText.length;
    if (boundary <= start) return '';
    _spokenUpTo[id] = boundary;
    return fullText.substring(start, boundary).trim();
  }

  /// Returns the remaining unspoken tail of [fullText] for [id] and stops
  /// tracking it. Use only once an utterance is known to be complete (a
  /// final, non-streaming reply) -- never after an interruption.
  String finish(String id, String fullText) {
    final start = _spokenUpTo.remove(id) ?? 0;
    _scannedUpTo.remove(id);
    if (start >= fullText.length) return '';
    return fullText.substring(start).trim();
  }

  /// Stops tracking [id] without returning its unspoken tail. Use for
  /// barge-in / interruption, where the remainder must never be spoken.
  void discard(String id) {
    _spokenUpTo.remove(id);
    _scannedUpTo.remove(id);
  }

  /// Index just past the last sentence-ending punctuation in [text], or -1
  /// when no sentence has completed yet.
  static int _lastSentenceBoundary(String text, int start) {
    var last = -1;
    for (var i = start; i < text.length; i++) {
      final char = text.codeUnitAt(i);
      if (char == 46 || char == 33 || char == 63 || char == 10) {
        last = i + 1;
      }
    }
    return last;
  }
}
