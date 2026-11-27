import 'dart:async';

import 'package:uuid/uuid.dart';

import '../core/memory/memory_crypto.dart';
import '../startup/neura_prefs_cache.dart';

/// One parked worry.
class ParkedWorry {
  final String id;
  final String text;
  final DateTime parkedAt;

  /// A small next step the user chose at worry time, if any.
  final String? step;

  /// Not shown again before this time ("keep for later").
  final DateTime? snoozedUntil;

  const ParkedWorry({
    required this.id,
    required this.text,
    required this.parkedAt,
    this.step,
    this.snoozedUntil,
  });

  ParkedWorry copyWith({String? step, DateTime? snoozedUntil}) => ParkedWorry(
        id: id,
        text: text,
        parkedAt: parkedAt,
        step: step ?? this.step,
        snoozedUntil: snoozedUntil ?? this.snoozedUntil,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'parked': parkedAt.toIso8601String(),
        if (step != null) 'step': step,
        if (snoozedUntil != null) 'snoozed': snoozedUntil!.toIso8601String(),
      };

  static ParkedWorry? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final text = value['text'];
    final parked = DateTime.tryParse('${value['parked']}');
    if (id is! String || text is! String || parked == null || text.isEmpty) {
      return null;
    }
    final step = value['step'];
    final snoozed = value['snoozed'];
    return ParkedWorry(
      id: id,
      text: text,
      parkedAt: parked,
      step: step is String ? step : null,
      snoozedUntil: snoozed is String ? DateTime.tryParse(snoozed) : null,
    );
  }
}

/// Worry parking: a CBT "worry time" technique. During the day the user
/// parks a worry ("park it: the rent") instead of turning it over; at the
/// worry time they chose, Neura brings the parked worries back to sort into
/// a small step, letting go, or keeping for later.
///
/// Worries are encrypted with the device memory key, stay on this device and
/// never enter a model prompt.
class NeuraWorryParking {
  NeuraWorryParking({
    Future<String> Function(Map<String, dynamic>)? encrypt,
    Future<Map<String, dynamic>> Function(String)? decrypt,
    DateTime Function()? now,
  })  : _encrypt = encrypt ??
            ((json) async => (await MemoryCrypto.demo()).encryptJson(json)),
        _decrypt = decrypt ??
            ((blob) async => (await MemoryCrypto.demo()).decryptJson(blob)),
        _now = now ?? DateTime.now;

  static final NeuraWorryParking instance = NeuraWorryParking();

  static const storageKey = 'neura.worry_parking.v1';
  static const hourKey = 'neura.worry_time.hour';
  static const offeredKey = 'neura.worry_time.offered';
  static const maxWorries = 30;
  static const maxLength = 300;
  static const defaultHour = 18;

  static final _uuid = Uuid();
  final Future<String> Function(Map<String, dynamic>) _encrypt;
  final Future<Map<String, dynamic>> Function(String) _decrypt;
  final DateTime Function() _now;
  Future<void> _tail = Future<void>.value();

  /// "park it: ...", "park this worry: ...", "park this: ...". Returns the
  /// worry, or null when the message is not a parking request.
  static String? worryFrom(String message) {
    final match = RegExp(
      r'^\s*park\s+(?:it|this(?:\s+worry)?|(?:a|my|the)\s+worry)\s*[:,\-–—]?\s*',
      caseSensitive: false,
    ).firstMatch(message);
    if (match == null) return null;
    final text = message.substring(match.end).trim();
    return text.isEmpty ? null : text;
  }

  /// The hour (0-23) worry time starts.
  int get hour => (NeuraPrefsCache.prefsOrNull?.getInt(hourKey) ?? defaultHour)
      .clamp(0, 23);

  Future<void> setHour(int value) =>
      NeuraPrefsCache.prefs.setInt(hourKey, value.clamp(0, 23));

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<List<ParkedWorry>> _read() async {
    final blob = NeuraPrefsCache.prefs.getString(storageKey);
    if (blob == null) return [];
    final json = await _decrypt(blob);
    final items = json['worries'];
    if (items is! List) return [];
    return items.map(ParkedWorry.fromJson).whereType<ParkedWorry>().toList();
  }

  Future<void> _write(List<ParkedWorry> worries) async {
    final blob = await _encrypt({
      'worries': [for (final worry in worries) worry.toJson()],
    });
    if (!await NeuraPrefsCache.prefs.setString(storageKey, blob)) {
      throw StateError('The worry could not be saved.');
    }
  }

  Future<List<ParkedWorry>> list() => _serial(_read);

  Future<ParkedWorry> park(String text) => _serial(() async {
        final clean = text.trim();
        if (clean.isEmpty) throw ArgumentError('There is nothing to park.');
        if (clean.length > maxLength) {
          throw ArgumentError('Park it in up to $maxLength characters.');
        }
        final worry = ParkedWorry(
          id: _uuid.v4(),
          text: clean,
          parkedAt: _now(),
        );
        final worries = [...await _read(), worry];
        while (worries.length > maxWorries) {
          worries.removeAt(0);
        }
        await _write(worries);
        return worry;
      });

  Future<void> _update(String id, ParkedWorry Function(ParkedWorry) change) =>
      _serial(() async {
        final worries = await _read();
        await _write([
          for (final worry in worries) worry.id == id ? change(worry) : worry,
        ]);
      });

  /// "Let it go": the worry is deleted.
  Future<void> letGo(String id) => _serial(() async {
        final worries = await _read();
        worries.removeWhere((worry) => worry.id == id);
        await _write(worries);
      });

  /// A small step the user chose; the worry stays until they let it go.
  Future<void> addStep(String id, String step) {
    final clean = step.trim();
    if (clean.isEmpty) return Future.value();
    final bounded =
        clean.length > maxLength ? clean.substring(0, maxLength) : clean;
    return _update(id, (worry) => worry.copyWith(step: bounded));
  }

  /// "Keep for later": back at the next worry time.
  Future<void> keepForLater(String id) =>
      _update(id, (worry) => worry.copyWith(snoozedUntil: nextWorryTime()));

  /// The next start of worry time after now.
  DateTime nextWorryTime() {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day, hour);
    return now.isBefore(today) ? today : today.add(const Duration(days: 1));
  }

  /// Worries to review now: parked before today's worry time began and not
  /// snoozed past now. Empty before worry time.
  Future<List<ParkedWorry>> due() async {
    final now = _now();
    final start = DateTime(now.year, now.month, now.day, hour);
    if (now.isBefore(start)) return const [];
    final worries = await list();
    return [
      for (final worry in worries)
        if (worry.parkedAt.isBefore(start) &&
            (worry.snoozedUntil == null || !worry.snoozedUntil!.isAfter(now)))
          worry,
    ];
  }

  /// Whether to offer worry time now: due worries and not offered today.
  Future<int> offerCount() async {
    final today = _now().toIso8601String().substring(0, 10);
    if (NeuraPrefsCache.prefs.getString(offeredKey) == today) return 0;
    final count = (await due()).length;
    if (count > 0) await NeuraPrefsCache.prefs.setString(offeredKey, today);
    return count;
  }
}
