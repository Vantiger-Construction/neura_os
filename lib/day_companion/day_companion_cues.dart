/// These rules only receive one finalized, on-device utterance at a time.
enum PenthouseCue {
  lightOn,
  lightOff,
  openCurtains,
  closeCurtains,
  windDown,
  focus
}

class DayCompanionCues {
  static final _address =
      RegExp(r'^(?:hey\s+)?neura\b[\s,:-]*', caseSensitive: false);
  static final _ending = RegExp(r'[.!?]+$');
  static final _note = RegExp(
    r"^(?:i (?:need to|plan to|promised to|prefer|want to remember|have an? (?:appointment|meeting))|my (?:goal is|appointment is|meeting is))\s+\S",
    caseSensitive: false,
  );
  static final _remember =
      RegExp(r'^(?:please )?remember (?:that )?', caseSensitive: false);
  static final _sensitive = RegExp(
    r'\b(?:password|passcode|pin|bank account|social security|credit card|verification code|access token)\b|\d{7,}',
    caseSensitive: false,
  );

  static String _words(String text) =>
      text.trim().replaceFirst(_address, '').replaceFirst(_ending, '').trim();

  static bool wantsStop(String text) => const {
        'stop listening',
        'pause listening'
      }.contains(_words(text).toLowerCase());

  static PenthouseCue? roomCue(String text) =>
      switch (_words(text).replaceAll('’', "'").toLowerCase()) {
        'turn on the lamp' || 'turn the lamp on' => PenthouseCue.lightOn,
        'turn off the lamp' || 'turn the lamp off' => PenthouseCue.lightOff,
        'open the curtains' => PenthouseCue.openCurtains,
        'close the curtains' => PenthouseCue.closeCurtains,
        "i'm winding down" || 'i am winding down' => PenthouseCue.windDown,
        'i need to focus' ||
        "i'm ready to read" ||
        'i am ready to read' =>
          PenthouseCue.focus,
        _ => null,
      };

  static String? note(String text) {
    if (text.length > 320 ||
        text.codeUnits.any((c) => c < 32 || c == 127) ||
        _sensitive.hasMatch(text) ||
        text.trimRight().endsWith('?')) {
      return null;
    }
    final words = text.trim().replaceFirst(_address, '');
    final prefix = _remember.firstMatch(words);
    final value = prefix == null ? words : words.substring(prefix.end).trim();
    if (value.isEmpty || (prefix == null && !_note.hasMatch(words))) {
      return null;
    }
    return value;
  }
}
