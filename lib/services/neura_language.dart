/// The languages Neura listens in, understands and answers in.
///
/// Pure Dart: no audio, storage or network. Recognizers report a code; typed
/// or untagged text is guessed from common words. Callers decide what to do
/// with the result, and English stays the default when nothing is clear.
enum NeuraLanguage {
  en('en', 'English', 'English', 'en-US'),
  es('es', 'Spanish', 'Español', 'es-ES'),
  it('it', 'Italian', 'Italiano', 'it-IT'),
  de('de', 'German', 'Deutsch', 'de-DE'),
  fr('fr', 'French', 'Français', 'fr-FR');

  const NeuraLanguage(this.code, this.englishName, this.nativeName, this.tag);

  /// Two-letter code, as recognizers and the native channels use it.
  final String code;
  final String englishName;

  /// The language's own name, shown in pickers so people can find it.
  final String nativeName;

  /// The default regional tag for recognizers and voices.
  final String tag;

  /// "es", "es-MX", "es_ES", "<|es|>" or "Spanish" give [es]. Anything else,
  /// including languages Neura does not speak, gives null.
  static NeuraLanguage? fromCode(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.trim().toLowerCase().replaceAll(RegExp(r'[<|>]'), '');
    if (cleaned.isEmpty || cleaned.length > 32) return null;
    final primary = cleaned.split(RegExp(r'[-_]')).first;
    for (final language in values) {
      if (primary == language.code ||
          cleaned == language.englishName.toLowerCase() ||
          cleaned == language.nativeName.toLowerCase()) {
        return language;
      }
    }
    return null;
  }
}

/// A best guess at which of Neura's languages a short message is in.
///
/// It scores frequent function words and a few letters that belong to one
/// language. It answers only when one language clearly wins, so a name or a
/// one-word reply never switches the conversation by itself.
abstract final class NeuraLanguageGuess {
  static final RegExp _word = RegExp(r"[\p{L}']+", unicode: true);

  // Words that are frequent in one language and rare in the others. Words the
  // languages share ("a", "la", "de", "un", "no") are deliberately absent.
  static final Map<NeuraLanguage, Set<String>> _words = {
    NeuraLanguage.en: _set(
      "the and is are you i i'm it it's what how this that with have my me "
      "was not don't can do to of for about feel today please yes just "
      'really would could need want',
    ),
    NeuraLanguage.es: _set(
      'el los las es está estoy estás que qué y por para con pero muy cómo '
      'tengo tienes quiero puedes hoy mi yo eres soy también gracias hola '
      'bien necesito siento ayuda ahora mañana nada algo cuando donde dónde '
      'sí una del al lo le nos',
    ),
    NeuraLanguage.it: _set(
      'il gli è sono che e per con ma molto come ho hai voglio puoi oggi '
      'mio mia io sei anche grazie ciao bene bisogno sento aiuto adesso '
      'domani niente qualcosa quando dove non della del di questo questa '
      'perché cosa mi ti ci una uno sto stai',
    ),
    NeuraLanguage.de: _set(
      'der die das und ist bin bist ich du nicht mit für aber sehr wie habe '
      'hast will kannst heute mein meine auch danke hallo gut brauche fühle '
      'hilfe jetzt morgen nichts etwas wenn wo was ein eine es mir mich '
      'dich dir ja nein zu auf noch',
    ),
    NeuraLanguage.fr: _set(
      "le les est suis es que qui et pour avec mais très comment j'ai tu je "
      "veux peux aujourd aujourd'hui mon ma mes aussi merci bonjour salut "
      'bien besoin sens aide maintenant demain rien quelque quand où pas ne '
      "des du une ce c'est moi toi oui vous nous m'aider",
    ),
  };

  static Set<String> _set(String words) => words.split(' ').toSet();

  // Letters used by only one of the five languages.
  static const Map<NeuraLanguage, String> _letters = {
    NeuraLanguage.es: 'ñ¿¡',
    NeuraLanguage.de: 'ßäöü',
    NeuraLanguage.fr: 'çœêâîûë',
    NeuraLanguage.it: 'ìò',
  };

  /// The clear winner, or null when the text is too short or mixed.
  static NeuraLanguage? of(String text) {
    final lower = text.toLowerCase();
    final words = _word
        .allMatches(lower)
        .map((m) => m.group(0)!)
        .take(80)
        .toList(growable: false);
    if (words.isEmpty) return null;
    final scores = <NeuraLanguage, double>{
      for (final language in NeuraLanguage.values) language: 0,
    };
    for (final word in words) {
      for (final entry in _words.entries) {
        if (entry.value.contains(word)) {
          scores[entry.key] = scores[entry.key]! + 1;
        }
      }
    }
    for (final entry in _letters.entries) {
      for (final rune in lower.runes) {
        if (entry.value.contains(String.fromCharCode(rune))) {
          scores[entry.key] = scores[entry.key]! + 1.5;
        }
      }
    }
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked[0];
    final second = ranked[1];
    // At least two signals, and a clear lead over the runner-up.
    if (best.value < 2) return null;
    if (best.value - second.value < 1.5 && best.value < second.value * 1.6) {
      return null;
    }
    return best.key;
  }
}

/// The per-turn note that asks the model to answer in the person's language.
///
/// Like the spoken-turn cue, it goes with the newest turn, never into the
/// system prompt. English needs no note; the prompt is already English.
abstract final class NeuraLanguageCue {
  static String forLanguage(NeuraLanguage? language) {
    if (language == null || language == NeuraLanguage.en) return '';
    final name = language.englishName;
    return 'They are speaking $name. Reply only in natural, warm $name, '
        'even though these instructions are in English. Keep names and '
        'quoted words as they are.';
  }
}
