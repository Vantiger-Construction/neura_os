/// Honest offline facts. The small on-device model answers from memory and
/// can state wrong numbers with confidence. When someone asks a factual
/// question and the reply carries specifics (numbers, years, amounts), Neura
/// says plainly that she is answering from memory; any dose gets a stronger
/// pointer to a pharmacist or doctor.
///
/// Text-only rules on the question and the reply; nothing is stored or sent.
class NeuraFactCheck {
  const NeuraFactCheck._();

  static const memoryCaveat = "I'm answering from memory on this computer, "
      'so please double-check those details. For an answer checked against '
      'a source, use the offline reference shelf.';

  static const doseCaveat = 'Please check any dose or medicine amount with '
      'a pharmacist or doctor before acting on it.';

  static final _factQuestion = RegExp(
    r"\b(who|when|where|which|how (many|much|long|far|old|tall|big|often)|"
    r"what (is|are|was|were|year|date|time)|what's|define|population|"
    r'capital|distance|price|cost|height|weight|temperature|dose|dosage|'
    r'calories|percent|statistics?)\b',
    caseSensitive: false,
  );

  static final _specific = RegExp(
    r'\d|\b(january|february|march|april|may|june|july|august|september|'
    r'october|november|december|million|billion|thousand|hundred|percent)\b',
    caseSensitive: false,
  );

  static final _doseWords = RegExp(
    r'\b(mg|mcg|milligrams?|micrograms?|ml|millilit(?:er|re)s?|doses?|dosage|'
    r'tablets?|pills?|capsules?|ibuprofen|paracetamol|acetaminophen|aspirin|'
    r'insulin|medication|medicine)\b',
    caseSensitive: false,
  );

  static bool asksForFacts(String question) => _factQuestion.hasMatch(question);

  static bool hasSpecifics(String reply) => _specific.hasMatch(reply);

  static bool _mentionsDose(String question, String reply) =>
      _doseWords.hasMatch(reply) &&
      RegExp(r'\d').hasMatch(reply) &&
      (_doseWords.hasMatch(question) || asksForFacts(question));

  /// The line to add after [reply] to [question], or null when none fits.
  static String? caveatFor(String question, String reply) {
    if (reply.trim().isEmpty) return null;
    if (_mentionsDose(question, reply)) return doseCaveat;
    if (asksForFacts(question) && hasSpecifics(reply)) return memoryCaveat;
    return null;
  }
}
