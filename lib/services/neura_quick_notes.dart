import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/memory/memory_crypto.dart';
import '../startup/neura_prefs_cache.dart';
import 'neura_language.dart';

/// How a note was made.
enum NeuraQuickNoteKind {
  /// One thing the person asked Neura to write down.
  note,

  /// Everything Neura heard while taking notes, until told to stop.
  transcript,
}

/// One note: words the person asked Neura to keep, in the language said.
class NeuraQuickNote {
  const NeuraQuickNote({
    required this.id,
    required this.text,
    required this.createdAt,
    this.kind = NeuraQuickNoteKind.note,
    this.languages = const [],
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final NeuraQuickNoteKind kind;

  /// The languages heard in this note, in the order they first appeared.
  final List<NeuraLanguage> languages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'created': createdAt.toIso8601String(),
        if (kind != NeuraQuickNoteKind.note) 'kind': kind.name,
        if (languages.isNotEmpty)
          'languages': [for (final language in languages) language.code],
      };

  static NeuraQuickNote? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final text = value['text'];
    final created = DateTime.tryParse('${value['created']}');
    if (id is! String || text is! String || created == null) return null;
    final kind = NeuraQuickNoteKind.values
            .where((kind) => kind.name == value['kind'])
            .firstOrNull ??
        NeuraQuickNoteKind.note;
    if (text.isEmpty || text.length > NeuraQuickNotes.maxLength(kind)) {
      return null;
    }
    final languages = value['languages'];
    return NeuraQuickNote(
      id: id,
      text: text,
      createdAt: created,
      kind: kind,
      languages: languages is List
          ? languages
              .map((code) => NeuraLanguage.fromCode(code?.toString()))
              .whereType<NeuraLanguage>()
              .toSet()
              .toList(growable: false)
          : const [],
    );
  }
}

/// Notes the person asks Neura to take ("Neura, take a note: ...", "Neura,
/// toma nota ...") and transcripts of note-taking sessions.
///
/// Notes are encrypted with this device's memory key and kept only here.
/// They are not journal entries and are never copied into companion memory
/// or a model prompt; the person reads, copies or deletes them. A data wipe
/// erases them with the rest of the device's preferences and its key.
class NeuraQuickNotes {
  NeuraQuickNotes({
    Future<String> Function(Map<String, dynamic>)? encrypt,
    Future<Map<String, dynamic>> Function(String)? decrypt,
    DateTime Function()? now,
  })  : _encrypt = encrypt ??
            ((json) async => (await MemoryCrypto.demo()).encryptJson(json)),
        _decrypt = decrypt ??
            ((blob) async => (await MemoryCrypto.demo()).decryptJson(blob)),
        _now = now ?? DateTime.now;

  static final NeuraQuickNotes instance = NeuraQuickNotes();

  @visibleForTesting
  static const storageKey = 'neura.quick_notes.v1';
  static const maxNotes = 100;
  static const maxNoteLength = 2000;
  static const maxTranscriptLength = 20000;

  static int maxLength(NeuraQuickNoteKind kind) =>
      kind == NeuraQuickNoteKind.transcript
          ? maxTranscriptLength
          : maxNoteLength;

  static final _uuid = Uuid();
  final Future<String> Function(Map<String, dynamic>) _encrypt;
  final Future<Map<String, dynamic>> Function(String) _decrypt;
  final DateTime Function() _now;
  Future<void> _tail = Future<void>.value();

  /// Bumped after every change so open screens can reload.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<List<NeuraQuickNote>> _read() async {
    final blob = NeuraPrefsCache.prefs.getString(storageKey);
    if (blob == null) return [];
    final json = await _decrypt(blob);
    final notes = json['notes'];
    if (notes is! List) return [];
    return notes
        .map(NeuraQuickNote.fromJson)
        .whereType<NeuraQuickNote>()
        .toList();
  }

  Future<void> _write(List<NeuraQuickNote> notes) async {
    final blob = await _encrypt({
      'notes': [for (final note in notes) note.toJson()],
    });
    if (!await NeuraPrefsCache.prefs.setString(storageKey, blob)) {
      throw StateError('The note could not be saved.');
    }
    revision.value++;
  }

  /// Newest first.
  Future<List<NeuraQuickNote>> list() => _serial(() async {
        final notes = await _read();
        return notes.reversed.toList(growable: false);
      });

  /// Saves a note. The oldest note is dropped past [maxNotes].
  Future<NeuraQuickNote> add(
    String text, {
    NeuraQuickNoteKind kind = NeuraQuickNoteKind.note,
    Iterable<NeuraLanguage> languages = const [],
  }) =>
      _serial(() async {
        final clean = text.trim();
        if (clean.isEmpty) throw ArgumentError('The note is empty.');
        final limit = maxLength(kind);
        if (clean.length > limit) {
          throw ArgumentError('Notes can be up to $limit characters.');
        }
        final note = NeuraQuickNote(
          id: _uuid.v4(),
          text: clean,
          createdAt: _now(),
          kind: kind,
          languages: languages.toSet().toList(growable: false),
        );
        final notes = [...await _read(), note];
        while (notes.length > maxNotes) {
          notes.removeAt(0);
        }
        await _write(notes);
        return note;
      });

  Future<void> delete(String id) => _serial(() async {
        final notes = await _read();
        notes.removeWhere((note) => note.id == id);
        await _write(notes);
      });
}

/// The words heard while Neura takes notes, kept in memory until saved.
///
/// Bounded by [NeuraQuickNotes.maxTranscriptLength]; once full, further
/// phrases are refused so nothing is silently dropped from the middle.
class NeuraNoteTranscript {
  final List<String> _phrases = [];
  final List<NeuraLanguage> _languages = [];
  int _length = 0;

  bool get isEmpty => _phrases.isEmpty;
  int get count => _phrases.length;
  bool get isFull => _length >= NeuraQuickNotes.maxTranscriptLength;
  List<NeuraLanguage> get languages => List.unmodifiable(_languages);

  /// Adds one heard phrase; false once the transcript is full.
  bool add(String phrase, {NeuraLanguage? language}) {
    final clean = phrase.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return true;
    final cost = clean.length + (_phrases.isEmpty ? 0 : 1);
    if (_length + cost > NeuraQuickNotes.maxTranscriptLength) return false;
    _phrases.add(clean);
    _length += cost;
    if (language != null && !_languages.contains(language)) {
      _languages.add(language);
    }
    return true;
  }

  /// One phrase per line, as it was heard.
  String get text => _phrases.join('\n');

  void clear() {
    _phrases.clear();
    _languages.clear();
    _length = 0;
  }
}

/// The note-taking session the person started in chat: whether Neura is
/// writing down what she hears, and what she has written so far.
///
/// Only an explicit request starts it, after the person confirms on screen
/// that everyone being written down knows. Anything that stops listening
/// (leaving chat, the background, Safe Mode) pauses it; the words stay here,
/// in memory only, until the person saves or discards them. A data wipe
/// clears them.
class NeuraNoteSession {
  NeuraNoteSession._();

  static final NeuraNoteSession instance = NeuraNoteSession._();

  /// True while Neura is writing down what she hears.
  final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// Phrases written down so far, for the on-screen counter.
  final ValueNotifier<int> phrases = ValueNotifier<int>(0);

  final NeuraNoteTranscript _transcript = NeuraNoteTranscript();
  NeuraLanguage _language = NeuraLanguage.en;

  /// The language the person asked in, for Neura's short spoken replies.
  NeuraLanguage get language => _language;
  bool get hasUnsaved => !_transcript.isEmpty;
  bool get isFull => _transcript.isFull;

  void start(NeuraLanguage language) {
    _language = language;
    active.value = true;
  }

  /// Writes down one heard phrase. False when not taking notes or full.
  bool add(String phrase, {NeuraLanguage? language}) {
    if (!active.value) return false;
    final added = _transcript.add(phrase, language: language);
    phrases.value = _transcript.count;
    return added;
  }

  /// Stops writing; what was heard stays until saved or discarded.
  void pause() => active.value = false;

  /// Saves what was heard as one note and ends the session.
  Future<NeuraQuickNote?> save({NeuraQuickNotes? store}) async {
    active.value = false;
    if (_transcript.isEmpty) return null;
    final text = _transcript.text;
    final languages = _transcript.languages;
    final note = await (store ?? NeuraQuickNotes.instance).add(
      text,
      kind: NeuraQuickNoteKind.transcript,
      languages: languages,
    );
    discard();
    return note;
  }

  void discard() {
    active.value = false;
    _transcript.clear();
    phrases.value = 0;
  }

  void resetAfterDataWipe() => discard();
}
