import 'emotion_analysis_service.dart';

/// A quick, on-device read of how a message might land before it is sent.
/// Observations, never judgements: the user decides what to send.
class NeuraToneCheck {
  const NeuraToneCheck._();

  static const rewriteSystem = 'You help someone rewrite a message before '
      'they send it. Keep their meaning and what they need, in their voice '
      'and language. Make it calm, clear and kind: say how they feel and what '
      'they would like, without blame, sarcasm or insults. Do not add facts, '
      'apologies they did not make, or promises. Keep it about as long or '
      'shorter. Reply with only the rewritten message.';

  static final _absolutes = RegExp(
    r'\b(always|never|every\s+(single\s+)?time|nobody|everyone)\b',
    caseSensitive: false,
  );
  static final _blame = RegExp(
    r"\b(you\s+(always|never|don'?t\s+even|can'?t\s+even)|your\s+fault|"
    r"because\s+of\s+you|what\s+is\s+wrong\s+with\s+you)\b",
    caseSensitive: false,
  );
  static final _insult = RegExp(
    r'\b(stupid|idiot|idiotic|pathetic|ridiculous|useless|lazy|selfish|'
    r'incompetent|dumb|joke)\b',
    caseSensitive: false,
  );
  static final _sarcasm = RegExp(
    r'\b(thanks\s+a\s+lot|great\s+job|well\s+done|nice\s+going|'
    r'whatever|sure,?\s+fine|fine,?\s+whatever)\b',
    caseSensitive: false,
  );
  static final _shoutWord = RegExp(r'\b[A-Z]{3,}\b');

  /// Gentle observations about [message], most important first; empty when
  /// nothing stands out.
  static List<String> observe(String message) {
    final text = message.trim();
    if (text.isEmpty) return const [];
    final notes = <String>[];
    final read = const EmotionAnalysisService().read(text);
    if (read.primary != null && read.primary != 'joy') {
      notes.add(
        'It sounds ${EmotionRead.adjectives[read.primary]}. That is okay to '
        'say; saying it directly often lands better than showing it.',
      );
    }
    if (_insult.hasMatch(text)) {
      notes.add('Some words may read as insults and could shut the '
          'conversation down.');
    }
    if (_blame.hasMatch(text)) {
      notes.add('"You always / you never" can feel like blame. Try '
          'describing one moment and how it felt.');
    } else if (_absolutes.hasMatch(text)) {
      notes.add('Words like "always" and "never" invite an argument about '
          'the exceptions.');
    }
    if (_sarcasm.hasMatch(text)) {
      notes.add('Something here could read as sarcastic in text.');
    }
    final shouting = _shoutWord
        .allMatches(text)
        .where((m) =>
            !const {'OK', 'ASAP', 'FYI', 'USA', 'UK'}.contains(m.group(0)))
        .length;
    if (shouting >= 2) {
      notes.add('Capital letters can read as shouting.');
    }
    if ('!'.allMatches(text).length >= 3) {
      notes.add('Several exclamation marks can make it feel heated.');
    }
    return notes;
  }

  /// The user's message for the rewrite model, with who it is for.
  static String rewriteRequest(String message, {String to = ''}) {
    final who = to.trim();
    return '${who.isEmpty ? 'My message' : 'My message to $who'}:\n'
        '${message.trim()}';
  }
}
