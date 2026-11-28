/// Spots a small commitment in something the user just said ("I'll call my
/// sister tonight") so Neura can offer to keep it as a promise.
///
/// This only proposes. Nothing is saved unless the user taps to keep it, and
/// the message itself is never stored: only the short commitment they chose.
class PromiseCatcher {
  const PromiseCatcher._();

  /// Shortest and longest commitment worth offering, in characters.
  static const minLength = 4;
  static const maxLength = 80;

  static final _lead = RegExp(
    r"^(?:ok(?:ay)?[, ]+|tomorrow\s+)?(?:i\s*['’]ll|i\s+will|i\s*['’]m\s+going\s+to|"
    r"i\s+am\s+going\s+to|i\s+promise\s+to|remind\s+me\s+to"
    r")\s+",
    caseSensitive: false,
  );

  /// Phrases that make it something other than a small commitment.
  static final _notACommitment = RegExp(
    r"^(?:never|not|try|probably|maybe|see|think|feel|guess|let\s+you|"
    r"stop\s+talking|be\s+(?:fine|ok|okay|right|back)\b)\b",
    caseSensitive: false,
  );

  /// Words never offered as a promise, whatever surrounds them.
  static final _neverOffered = RegExp(
    r"\b(?:die|dying|kill|killing|hurt\s+(?:myself|me)|end\s+it|disappear|"
    r"suicide|overdose|cut\s+myself)\b",
    caseSensitive: false,
  );

  /// Where the commitment stops: the end of the sentence or a reason.
  static final _clauseEnd = RegExp(
    r'[.!?;\n]|,?\s+(?:but|because|since|though|cause)\b',
    caseSensitive: false,
  );

  /// The commitment in [message], cleaned up for a promise list, or null
  /// when the message holds none.
  static String? commitmentFrom(String message) {
    final text = message.trim();
    if (text.isEmpty || text.length > 600) return null;
    // Questions ask; they do not promise.
    if (text.contains('?')) return null;
    // Conservative offers: quoted, conditional and retracted statements are
    // easy to misread as commitments. Manual promise entry remains available.
    if (RegExp(
            r'["“”]|\b(?:if|unless|maybe|perhaps|might|not|never|'
            r"won['’]t|can['’]t)\b|changed my mind|no longer",
            caseSensitive: false)
        .hasMatch(text)) {
      return null;
    }
    final match = _lead.firstMatch(text);
    if (match == null) return null;
    var rest = text.substring(match.end);
    final end = _clauseEnd.firstMatch(rest);
    if (end != null) rest = rest.substring(0, end.start);
    rest = rest.trim().replaceAll(RegExp(r'\s+'), ' ');
    rest = rest.replaceAll(RegExp(r'[,:\-–—]+$'), '').trim();
    if (rest.length < minLength || rest.length > maxLength) return null;
    if (_notACommitment.hasMatch(rest)) return null;
    if (_neverOffered.hasMatch(text)) return null;
    // Needs a verb-like first word, not a pronoun or filler.
    final first = rest.split(' ').first.toLowerCase();
    const filler = {'it', 'that', 'this', 'you', 'be', 'do', 'so', 'just'};
    if (filler.contains(first)) return null;
    return rest[0].toUpperCase() + rest.substring(1);
  }
}
