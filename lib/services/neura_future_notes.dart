import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/memory/memory_crypto.dart';
import '../startup/neura_prefs_cache.dart';
import 'emotion_analysis_service.dart';

/// What a saved note is.
enum FutureNoteKind {
  /// Written on purpose: "note to future me: ...".
  note,

  /// A happy moment the user chose to keep when Neura offered.
  brightSpot,
}

/// One note the user wrote to their future self, or a bright spot they kept.
class FutureNote {
  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime? lastOfferedAt;
  final FutureNoteKind kind;

  const FutureNote({
    required this.id,
    required this.text,
    required this.createdAt,
    this.lastOfferedAt,
    this.kind = FutureNoteKind.note,
  });

  FutureNote offered(DateTime at) => FutureNote(
        id: id,
        text: text,
        createdAt: createdAt,
        lastOfferedAt: at,
        kind: kind,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'created': createdAt.toIso8601String(),
        if (lastOfferedAt != null) 'offered': lastOfferedAt!.toIso8601String(),
        if (kind != FutureNoteKind.note) 'kind': kind.name,
      };

  static FutureNote? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final text = value['text'];
    final created = DateTime.tryParse('${value['created']}');
    if (id is! String || text is! String || created == null) return null;
    if (text.isEmpty || text.length > NeuraFutureNotes.maxNoteLength) {
      return null;
    }
    final offered = value['offered'];
    final kind = FutureNoteKind.values
        .where((kind) => kind.name == value['kind'])
        .firstOrNull;
    return FutureNote(
      id: id,
      text: text,
      createdAt: created,
      lastOfferedAt: offered is String ? DateTime.tryParse(offered) : null,
      kind: kind ?? FutureNoteKind.note,
    );
  }
}

/// Notes to future you: written in a good moment, offered back when the
/// on-device emotion read senses a hard one.
///
/// Notes are encrypted with this device's memory key and kept only on this
/// device. They never enter a model prompt; Neura only offers to show them,
/// and only the user reads them. A local data wipe erases them with the key.
class NeuraFutureNotes {
  NeuraFutureNotes({
    Future<String> Function(Map<String, dynamic>)? encrypt,
    Future<Map<String, dynamic>> Function(String)? decrypt,
    DateTime Function()? now,
  })  : _encrypt = encrypt ??
            ((json) async => (await MemoryCrypto.demo()).encryptJson(json)),
        _decrypt = decrypt ??
            ((blob) async => (await MemoryCrypto.demo()).decryptJson(blob)),
        _now = now ?? DateTime.now;

  static final NeuraFutureNotes instance = NeuraFutureNotes();

  @visibleForTesting
  static const storageKey = 'neura.future_notes.v1';
  static const maxNotes = 30;
  static const maxNoteLength = 600;

  /// At most one offer in this window, so notes stay special.
  static const offerCooldown = Duration(days: 3);

  /// A note is not offered back within a day of being written.
  static const minimumAge = Duration(days: 1);

  static const _hardFeelings = {
    'sadness',
    'grief',
    'loneliness',
    'shame',
    'anxiety',
    'overwhelm',
    'exhaustion',
  };

  static final _uuid = Uuid();
  final Future<String> Function(Map<String, dynamic>) _encrypt;
  final Future<Map<String, dynamic>> Function(String) _decrypt;
  final DateTime Function() _now;
  Future<void> _tail = Future<void>.value();

  /// "note to future me: ..." and close variants. Returns the note text, or
  /// null when the message is not a note.
  static String? noteFrom(String message) {
    final match = RegExp(
      r'^\s*(?:a\s+)?note\s+(?:to|for)\s+(?:the\s+)?(?:future\s+me|my\s+future\s+self|future\s+self|future\s+you)\s*[:,\-–—]?\s*',
      caseSensitive: false,
    ).firstMatch(message);
    if (match == null) return null;
    final text = message.substring(match.end).trim();
    return text.isEmpty ? null : text;
  }

  /// Whether this read is a moment to offer a note back.
  static bool isHardMoment(EmotionRead read) =>
      read.masked ||
      (_hardFeelings.contains(read.primary) && read.intensity >= 0.4);

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<List<FutureNote>> _read() async {
    final blob = NeuraPrefsCache.prefs.getString(storageKey);
    if (blob == null) return [];
    final json = await _decrypt(blob);
    final notes = json['notes'];
    if (notes is! List) return [];
    return notes.map(FutureNote.fromJson).whereType<FutureNote>().toList();
  }

  Future<void> _write(List<FutureNote> notes) async {
    final blob = await _encrypt({
      'notes': [for (final note in notes) note.toJson()],
    });
    if (!await NeuraPrefsCache.prefs.setString(storageKey, blob)) {
      throw StateError('The note could not be saved.');
    }
  }

  Future<List<FutureNote>> list() => _serial(_read);

  /// Saves a note. The oldest note is dropped past [maxNotes].
  Future<FutureNote> add(
    String text, {
    FutureNoteKind kind = FutureNoteKind.note,
  }) =>
      _serial(() async {
        final clean = text.trim();
        if (clean.isEmpty) throw ArgumentError('The note is empty.');
        if (clean.length > maxNoteLength) {
          throw ArgumentError(
            'Notes can be up to $maxNoteLength characters.',
          );
        }
        final note = FutureNote(
          id: _uuid.v4(),
          text: clean,
          createdAt: _now(),
          kind: kind,
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

  /// A note to offer for this moment, or null. Marks it offered, so the same
  /// note rests longest before it comes back.
  Future<FutureNote?> offerFor(EmotionRead read) {
    if (!isHardMoment(read)) return Future.value();
    return _serial(() async {
      final now = _now();
      final notes = await _read();
      final recent = notes.any(
        (note) =>
            note.lastOfferedAt != null &&
            now.difference(note.lastOfferedAt!) < offerCooldown,
      );
      if (recent) return null;
      final ready = notes
          .where((note) => now.difference(note.createdAt) >= minimumAge)
          .toList()
        ..sort((a, b) {
          final at = a.lastOfferedAt ?? DateTime(0);
          final bt = b.lastOfferedAt ?? DateTime(0);
          final byOffer = at.compareTo(bt);
          if (byOffer != 0) return byOffer;
          // A note written on purpose comes before a saved bright spot.
          final byKind = a.kind.index.compareTo(b.kind.index);
          return byKind != 0 ? byKind : a.createdAt.compareTo(b.createdAt);
        });
      if (ready.isEmpty) return null;
      final chosen = ready.first.offered(now);
      await _write([
        for (final note in notes) note.id == chosen.id ? chosen : note,
      ]);
      return chosen;
    });
  }

  /// Bright spots saved on [day], for the morning note.
  Future<List<String>> brightSpotsOn(DateTime day) async {
    final notes = await _read();
    return [
      for (final note in notes)
        if (note.kind == FutureNoteKind.brightSpot &&
            note.createdAt.year == day.year &&
            note.createdAt.month == day.month &&
            note.createdAt.day == day.day)
          note.text,
    ];
  }

  /// Whether a bright spot was already offered to save today.
  static const brightSpotOfferKey = 'neura.bright_spot_offered.v1';
}
