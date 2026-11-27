/// How long hands-free voice waits after a recognized phrase before it
/// treats the turn as finished. People pause mid-thought ("I just feel like,
/// um..."), and replying at the first pause cuts them off.
///
/// Text-only rules on the words heard so far: no audio, nothing stored.
class NeuraTurnPatience {
  const NeuraTurnPatience._();

  /// A finished-sounding phrase: a short beat in case they keep going.
  static const settled = Duration(milliseconds: 700);

  /// A heavier message deserves a little more room before Neura answers.
  static const gentle = Duration(milliseconds: 1400);

  /// The words trail off mid-thought: wait for the rest.
  static const unfinished = Duration(milliseconds: 2600);

  /// Words that rarely end a thought when spoken last.
  static const _openEndings = {
    'and',
    'but',
    'so',
    'because',
    'cause',
    'or',
    'um',
    'uh',
    'erm',
    'hmm',
    'like',
    'the',
    'a',
    'an',
    'to',
    'i',
    'if',
    'when',
    'then',
    'which',
    'that',
    'my',
    'with',
    'of',
    'for',
    'about',
    'just',
    'is',
    'was',
    'are',
    'were',
    'im',
    'its',
    'maybe',
    'also',
    'since',
    'until',
    'though',
    'while',
    'well',
    'actually',
    'basically',
    'kinda',
    'gonna',
    'wanna',
    'think',
    'feel',
    'mean',
    'know',
    'really',
    'very',
    'at',
    'in',
    'on',
    'from',
  };

  /// Short replies that are complete on their own.
  static const _complete = {
    'yes',
    'yeah',
    'yep',
    'no',
    'nope',
    'okay',
    'ok',
    'thanks',
    'thank you',
    'hi',
    'hello',
    'hey',
    'bye',
    'goodbye',
    'sure',
    'right',
    'good',
    'fine',
    'great',
    'cool',
    'nice',
    'stop',
    'wait',
    'please',
  };

  static final _word = RegExp(r"[a-z]+(?:'[a-z]+)?");

  /// Whether [heard] sounds like the speaker stopped mid-thought.
  static bool soundsUnfinished(String heard) {
    final text = heard.trim().toLowerCase();
    if (text.isEmpty) return false;
    if (text.endsWith(',') ||
        text.endsWith('...') ||
        text.endsWith('…') ||
        text.endsWith('-')) {
      return true;
    }
    if (_complete.contains(text.replaceAll(RegExp(r'[.!?]+$'), ''))) {
      return false;
    }
    // A sentence mark from the recognizer means it heard an ending.
    if (RegExp(r'[.!?]$').hasMatch(text)) return false;
    final words = _word.allMatches(text).map((m) => m.group(0)!).toList();
    if (words.isEmpty) return false;
    return _openEndings.contains(words.last.replaceAll("'", ''));
  }

  /// The wait after the latest phrase. [heavy] is true when the on-device
  /// emotion read found a hard feeling in what was said.
  static Duration after(String heard, {bool heavy = false}) {
    if (soundsUnfinished(heard)) return unfinished;
    return heavy ? gentle : settled;
  }
}
