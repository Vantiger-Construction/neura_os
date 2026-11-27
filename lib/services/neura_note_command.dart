import 'neura_language.dart';

/// What a note request asks for.
enum NeuraNoteAction {
  /// Save the words that follow as one note.
  add,

  /// Start writing down everything said until told to stop.
  startTaking,

  /// Stop writing things down and save what was heard.
  stopTaking,
}

/// A recognized note request, in any of Neura's languages.
final class NeuraNoteCommand {
  const NeuraNoteCommand(this.action, this.language, [this.text = '']);

  final NeuraNoteAction action;

  /// The language the request was made in.
  final NeuraLanguage language;

  /// The note itself, for [NeuraNoteAction.add].
  final String text;

  static final _spaces = RegExp(r'\s+');
  static final _address = RegExp(
    r'^(?:hey|oye|ehi|hallo|dis|hé)?[\s,]*neura\b[\s,:!.]*',
    caseSensitive: false,
  );
  static final _edge = RegExp(r'^[\s,:;.!?¡¿\-–—]+|[\s,;]+$');

  // Longest phrases first within each action, so "take notes" is not read as
  // "take note" followed by the word "s".
  static const _start = <NeuraLanguage, List<String>>{
    NeuraLanguage.en: ['start taking notes', 'take notes', 'start notes'],
    NeuraLanguage.es: [
      'empieza a tomar notas',
      'comienza a tomar notas',
      'toma notas',
    ],
    NeuraLanguage.it: [
      'inizia a prendere appunti',
      'comincia a prendere appunti',
      'prendi appunti',
    ],
    NeuraLanguage.de: [
      'fang an mitzuschreiben',
      'fange an mitzuschreiben',
      'schreib mit',
      'schreibe mit',
    ],
    NeuraLanguage.fr: [
      'commence à prendre des notes',
      'commence a prendre des notes',
      'prends des notes',
    ],
  };

  static const _stop = <NeuraLanguage, List<String>>{
    NeuraLanguage.en: ['stop taking notes', 'stop notes', 'stop note taking'],
    NeuraLanguage.es: ['deja de tomar notas', 'para de tomar notas'],
    NeuraLanguage.it: ['smetti di prendere appunti', 'basta appunti'],
    NeuraLanguage.de: ['hör auf mitzuschreiben', 'hoer auf mitzuschreiben'],
    NeuraLanguage.fr: [
      'arrête de prendre des notes',
      'arrete de prendre des notes',
    ],
  };

  static const _add = <NeuraLanguage, List<String>>{
    NeuraLanguage.en: [
      'take a note',
      'make a note',
      'take note',
      'write down',
      'note that',
    ],
    NeuraLanguage.es: ['toma una nota', 'toma nota', 'anota', 'apunta'],
    NeuraLanguage.it: ['prendi un appunto', 'prendi nota', 'annota'],
    NeuraLanguage.de: ['mach eine notiz', 'schreib auf', 'notiere', 'notier'],
    NeuraLanguage.fr: ['prends une note', 'prends note', 'note que'],
  };

  // English and French both say "note: ..."; the words after it decide.
  static const _shared = 'note';

  /// Recognizes a request addressed to Neura ("Neura, take a note: ...",
  /// "Neura, toma nota ...", "Neura, prends des notes").
  ///
  /// [typed] text may also leave out the address when it uses a colon
  /// ("take a note: call the clinic"), which is never how speech arrives.
  static NeuraNoteCommand? parse(String message, {bool typed = false}) {
    final normalized =
        message.replaceAll(_spaces, ' ').replaceAll('’', "'").trim();
    if (normalized.isEmpty || normalized.length > 2000) return null;
    final addressEnd = _address.firstMatch(normalized)?.end ?? 0;
    final addressed = addressEnd > 0;
    if (!addressed && !typed) return null;
    final rest = normalized.substring(addressEnd);
    final lower = rest.toLowerCase();

    String? exact(String phrase) {
      final clean = lower.replaceFirst(RegExp(r'[\s.!?]+$'), '');
      final bare = clean.endsWith(' please')
          ? clean.substring(0, clean.length - 7)
          : clean;
      return bare == phrase ? phrase : null;
    }

    // Starting and stopping are whole requests; they carry no note text.
    if (addressed) {
      for (final entry in _stop.entries) {
        for (final phrase in entry.value) {
          if (exact(phrase) != null) {
            return NeuraNoteCommand(NeuraNoteAction.stopTaking, entry.key);
          }
        }
      }
      for (final entry in _start.entries) {
        for (final phrase in entry.value) {
          if (exact(phrase) != null) {
            return NeuraNoteCommand(NeuraNoteAction.startTaking, entry.key);
          }
        }
      }
    }

    for (final entry in _add.entries) {
      for (final phrase in entry.value) {
        if (!lower.startsWith(phrase)) continue;
        final after = rest.substring(phrase.length);
        // The phrase must end at a word boundary ("note" but not "notebook").
        if (after.isNotEmpty &&
            RegExp(r'^[\p{L}\p{N}]', unicode: true).hasMatch(after)) {
          continue;
        }
        // Typed requests without the address need an explicit colon.
        if (!addressed && !after.trimLeft().startsWith(':')) continue;
        final text = after.replaceAll(_edge, '').trim();
        if (text.isEmpty) return null;
        return NeuraNoteCommand(NeuraNoteAction.add, entry.key, text);
      }
    }
    if (lower.startsWith(_shared)) {
      final after = rest.substring(_shared.length);
      final boundary = after.isEmpty ||
          !RegExp(r'^[\p{L}\p{N}]', unicode: true).hasMatch(after);
      // Only when addressed: a typed "Note: ..." is usually conversation.
      if (boundary && addressed) {
        final text = after.replaceAll(_edge, '').trim();
        if (text.isEmpty) return null;
        return NeuraNoteCommand(
          NeuraNoteAction.add,
          NeuraLanguageGuess.of(text) ?? NeuraLanguage.en,
          text,
        );
      }
    }
    return null;
  }

  /// What Neura says after saving, in the language of the request.
  static String savedReply(NeuraLanguage language) => switch (language) {
        NeuraLanguage.en => 'Noted. It stays on this device.',
        NeuraLanguage.es => 'Anotado. Se queda en este dispositivo.',
        NeuraLanguage.it => 'Annotato. Resta su questo dispositivo.',
        NeuraLanguage.de => 'Notiert. Es bleibt auf diesem Gerät.',
        NeuraLanguage.fr => 'Noté. Ça reste sur cet appareil.',
      };

  /// What Neura says when she starts writing things down.
  static String startedReply(NeuraLanguage language) => switch (language) {
        NeuraLanguage.en =>
          "I'm taking notes. Say \"Neura, stop taking notes\" when you're done.",
        NeuraLanguage.es =>
          'Estoy tomando notas. Di "Neura, deja de tomar notas" cuando acabes.',
        NeuraLanguage.it =>
          'Sto prendendo appunti. Di "Neura, smetti di prendere appunti" quando hai finito.',
        NeuraLanguage.de =>
          'Ich schreibe mit. Sag "Neura, hör auf mitzuschreiben", wenn du fertig bist.',
        NeuraLanguage.fr =>
          'Je prends des notes. Dis « Neura, arrête de prendre des notes » quand tu as fini.',
      };

  /// What Neura says when she stops and saves the notes.
  static String stoppedReply(NeuraLanguage language) => switch (language) {
        NeuraLanguage.en => 'Notes saved on this device.',
        NeuraLanguage.es => 'Notas guardadas en este dispositivo.',
        NeuraLanguage.it => 'Appunti salvati su questo dispositivo.',
        NeuraLanguage.de => 'Notizen auf diesem Gerät gespeichert.',
        NeuraLanguage.fr => 'Notes enregistrées sur cet appareil.',
      };
}
