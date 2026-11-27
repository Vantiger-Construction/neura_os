import 'dart:convert';

/// Pure helpers that help Neura understand what was meant when a message was
/// spoken rather than typed. Nothing here touches audio, storage or the
/// network; callers decide what to persist and only with the person's consent.

/// Turns raw recognizer output into readable text.
///
/// Streaming transducer models (the Sherpa-ONNX Zipformer profile) emit
/// upper-case words without punctuation. The chat box, the local model and the
/// person all read sentence case better.
abstract final class NeuraSpokenText {
  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _pronounI = RegExp(r"\bi\b(?=$|[\s'’,.!?])");

  static String normalize(String raw) {
    final clean = raw.replaceAll(_spaces, ' ').trim();
    if (clean.isEmpty) return '';
    final letters = clean.replaceAll(RegExp(r'[^A-Za-z]'), '');
    // Leave mixed-case text from engines that already punctuate untouched.
    final shouting = letters.isNotEmpty && letters == letters.toUpperCase();
    if (!shouting) return clean;
    final lower = clean.toLowerCase().replaceAll(_pronounI, 'I');
    return lower[0].toUpperCase() + lower.substring(1);
  }
}

/// One phrase the recognizer keeps mishearing and what the person meant.
final class NeuraSpokenCorrection {
  NeuraSpokenCorrection({required String heard, required String meant})
      : heard = _clean(heard),
        meant = _clean(meant) {
    if (this.heard.isEmpty || this.meant.isEmpty) {
      throw const FormatException('Empty spoken correction.');
    }
    if (_words(this.heard) > maxWords || _words(this.meant) > maxWords) {
      throw const FormatException('Spoken correction is too long.');
    }
    if (this.heard.toLowerCase() == this.meant.toLowerCase()) {
      throw const FormatException('Spoken correction changes nothing.');
    }
  }

  static const maxWords = 4;
  static const maxChars = 64;

  final String heard;
  final String meant;

  Map<String, String> toJson() => {'heard': heard, 'meant': meant};

  static NeuraSpokenCorrection? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final heard = json['heard'];
    final meant = json['meant'];
    if (heard is! String || meant is! String) return null;
    try {
      return NeuraSpokenCorrection(heard: heard, meant: meant);
    } on FormatException {
      return null;
    }
  }

  static String _clean(String value) {
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > maxChars ||
        text.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      return '';
    }
    return text;
  }

  static int _words(String text) => text.split(' ').length;
}

/// A small, bounded list of the person's own corrections, applied to future
/// transcripts before they are shown or sent. Entries are added only after the
/// person confirms them, so the list never fills from conversation by itself.
final class NeuraSpokenLexicon {
  NeuraSpokenLexicon([Iterable<NeuraSpokenCorrection> entries = const []]) {
    for (final entry in entries) {
      add(entry);
    }
  }

  static const maxEntries = 64;

  final List<NeuraSpokenCorrection> _entries = [];

  List<NeuraSpokenCorrection> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;

  /// Adds or replaces the entry for [correction.heard]; the newest wins and
  /// the oldest entry is dropped once [maxEntries] is reached.
  void add(NeuraSpokenCorrection correction) {
    _entries.removeWhere(
      (entry) => entry.heard.toLowerCase() == correction.heard.toLowerCase(),
    );
    _entries.add(correction);
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
  }

  bool remove(String heard) {
    final before = _entries.length;
    _entries.removeWhere(
      (entry) => entry.heard.toLowerCase() == heard.trim().toLowerCase(),
    );
    return _entries.length != before;
  }

  void clear() => _entries.clear();

  /// Replaces every whole-word, case-insensitive occurrence of a heard phrase.
  /// Longer phrases are applied first so "camera hock" wins over "hock".
  String apply(String text) {
    if (_entries.isEmpty || text.isEmpty) return text;
    final ordered = [..._entries]
      ..sort((a, b) => b.heard.length.compareTo(a.heard.length));
    var result = text;
    for (final entry in ordered) {
      // Letters of every language count as word characters, so "café"
      // is not matched inside "cafés" and "über" stays whole.
      final pattern = RegExp(
        '(?<![\\p{L}\\p{N}])${RegExp.escape(entry.heard)}(?![\\p{L}\\p{N}])',
        caseSensitive: false,
        unicode: true,
      );
      result = result.replaceAll(pattern, entry.meant);
    }
    return result;
  }

  String encode() => jsonEncode([for (final entry in _entries) entry.toJson()]);

  static NeuraSpokenLexicon decode(String? raw) {
    if (raw == null || raw.isEmpty) return NeuraSpokenLexicon();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return NeuraSpokenLexicon();
      return NeuraSpokenLexicon(
        decoded
            .map(NeuraSpokenCorrection.tryFromJson)
            .whereType<NeuraSpokenCorrection>(),
      );
    } on FormatException {
      return NeuraSpokenLexicon();
    }
  }

  /// When the person fixes a transcript before sending it, finds the single
  /// short span they changed. Returns null for rewrites, pure additions or
  /// deletions, and edits longer than [NeuraSpokenCorrection.maxWords] words,
  /// because those are not recognition mistakes worth remembering.
  static NeuraSpokenCorrection? proposeFrom({
    required String heard,
    required String sent,
  }) {
    final a = _tokens(heard);
    final b = _tokens(sent);
    if (a.isEmpty || b.isEmpty) return null;
    var start = 0;
    final shorter = a.length < b.length ? a.length : b.length;
    while (start < shorter && _same(a[start], b[start])) {
      start++;
    }
    var endA = a.length;
    var endB = b.length;
    while (endA > start && endB > start && _same(a[endA - 1], b[endB - 1])) {
      endA--;
      endB--;
    }
    final wrong = a.sublist(start, endA);
    final right = b.sublist(start, endB);
    if (wrong.isEmpty || right.isEmpty) return null;
    if (wrong.length > NeuraSpokenCorrection.maxWords ||
        right.length > NeuraSpokenCorrection.maxWords) {
      return null;
    }
    // Most of the sentence must survive; otherwise it was rewritten.
    final kept = a.length - wrong.length;
    if (kept < 1 || kept * 2 < a.length) return null;
    try {
      return NeuraSpokenCorrection(
        heard: wrong.join(' '),
        meant: right.join(' '),
      );
    } on FormatException {
      return null;
    }
  }

  static List<String> _tokens(String text) => text
      .replaceAll(RegExp(r'[.,!?;:]+(?=\s|$)'), '')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();

  // Case-sensitive on purpose: a fixed capital ("Camera Hawk") is part of the
  // correction the person made.
  static bool _same(String a, String b) => a == b;
}

/// The per-turn note that tells the local model a message was spoken.
///
/// It is sent with the newest turn, never in the system prompt (a changing
/// system prompt forces the local model to re-read the whole conversation).
abstract final class NeuraSpokenTurnCue {
  static const _spoken =
      'They said this aloud; offline speech recognition can mishear words. '
      'Answer what they most likely meant from the conversation, not the '
      'literal words. If two meanings are plausible and the choice matters, '
      'ask one short question instead of guessing.';

  /// Joins the spoken note with [otherCue] (for example the emotion cue),
  /// keeping the result within [maxBytes]. The other cue is kept whole or
  /// dropped, never cut mid-sentence.
  static String build({String otherCue = '', int maxBytes = 512}) {
    final other = otherCue.trim();
    if (other.isEmpty) return _fit(_spoken, maxBytes);
    final joined = '$_spoken $other';
    if (utf8.encode(joined).length <= maxBytes) return joined;
    return _fit(_spoken, maxBytes);
  }

  static String _fit(String text, int maxBytes) =>
      utf8.encode(text).length <= maxBytes ? text : '';
}
