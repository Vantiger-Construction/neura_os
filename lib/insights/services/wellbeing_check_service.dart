import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, visibleForTesting;

import '../../core/memory/memory_crypto.dart';
import '../../profiles/local_profile_service.dart';
import '../../startup/neura_prefs_cache.dart';

/// One completed monthly wellbeing check.
class WellbeingCheckResult {
  const WellbeingCheckResult({required this.takenAt, required this.answers});

  final DateTime takenAt;

  /// One score per question, 0 (at no time) to 5 (all of the time).
  final List<int> answers;

  /// The raw score, 0-25.
  int get raw => answers.fold(0, (sum, answer) => sum + answer);

  /// The score on the 0-100 scale the WHO-5 reports.
  int get percent => raw * 4;

  Map<String, dynamic> toJson() => {
        'taken': takenAt.toIso8601String(),
        'answers': answers,
      };

  static WellbeingCheckResult? fromJson(Object? value) {
    if (value is! Map) return null;
    final taken = DateTime.tryParse('${value['taken']}');
    final answers = value['answers'];
    if (taken == null || answers is! List) return null;
    if (answers.length != WellbeingCheckService.questions.length ||
        answers.any((answer) => answer is! int)) {
      return null;
    }
    final scores = answers.cast<int>().toList();
    if (scores.length != WellbeingCheckService.questions.length) return null;
    if (scores.any((score) => score < 0 || score > 5)) return null;
    return WellbeingCheckResult(takenAt: taken, answers: scores);
  }
}

/// How a score reads. Not a diagnosis: a prompt to notice and, when it is
/// low, to talk with someone.
enum WellbeingBand {
  /// App presentation band for 0-28; not a diagnostic threshold.
  low,

  /// App presentation band for 29-50; not a population comparison.
  reduced,

  /// More frequent self-reported positive experiences (51-100).
  good;

  static WellbeingBand of(int percent) {
    if (percent <= 28) return low;
    if (percent <= 50) return reduced;
    return good;
  }
}

/// A monthly wellbeing check using the WHO-5 Well-Being Index, a short,
/// widely used questionnaire published by the World Health Organization.
///
/// Results are encrypted with the device memory key, stay on this device,
/// never enter a model prompt and are removed by a local data wipe. Profile
/// sessions cannot read or save them.
class WellbeingCheckService extends ChangeNotifier {
  WellbeingCheckService({
    Future<String> Function(Map<String, dynamic>)? encrypt,
    Future<Map<String, dynamic>> Function(String)? decrypt,
    DateTime Function()? now,
    bool Function()? allowed,
  })  : _encrypt = encrypt ??
            ((json) async {
              final crypto = await MemoryCrypto.demo();
              crypto.requireOsBackedKey();
              return crypto.encryptJson(json);
            }),
        _decrypt = decrypt ??
            ((blob) async => (await MemoryCrypto.demo()).decryptJson(blob)),
        _now = now ?? DateTime.now,
        _allowed = allowed ?? (() => !LocalProfileService.instance.enabled) {
    _owners.add(WeakReference(this));
  }

  static final WellbeingCheckService instance = WellbeingCheckService();

  static const storageKey = 'neura.wellbeing_check.v1';

  /// Results kept; the oldest go first.
  static const maxResults = 24;

  /// How often the check is offered.
  static const interval = Duration(days: 28);

  /// "Over the last two weeks..."
  static const questions = <String>[
    'I have felt cheerful and in good spirits',
    'I have felt calm and relaxed',
    'I have felt active and vigorous',
    'I woke up feeling fresh and rested',
    'My daily life has been filled with things that interest me',
  ];

  /// Answer labels; the index is the score.
  static const choices = <String>[
    'At no time',
    'Some of the time',
    'Less than half of the time',
    'More than half of the time',
    'Most of the time',
    'All of the time',
  ];

  final Future<String> Function(Map<String, dynamic>) _encrypt;
  final Future<Map<String, dynamic>> Function(String) _decrypt;
  final DateTime Function() _now;
  final bool Function() _allowed;
  Future<void> _tail = Future<void>.value();
  static final Set<WeakReference<WellbeingCheckService>> _owners = {};
  static bool _wipeSuspended = false;
  @visibleForTesting
  static Duration fullWipeDrainTimeout = const Duration(seconds: 30);
  int _generation = 0;
  bool _suspended = false;

  // Admission closes synchronously. Already-submitted native writes must drain
  // before the wipe may delete preferences or keys. Failure is not success.
  void suspendForDataWipe() {
    _suspended = true;
    invalidateSession();
  }

  void invalidateSession() {
    _generation++;
    notifyListeners();
  }

  Future<void> drainForDataWipe() => _tail.timeout(fullWipeDrainTimeout);

  static void suspendAllForDataWipe() {
    _wipeSuspended = true;
    _owners.removeWhere((reference) => reference.target == null);
    for (final reference in _owners) {
      reference.target?.suspendForDataWipe();
    }
  }

  static Future<void> drainAllForDataWipe() => Future.wait([
        for (final reference in _owners)
          if (reference.target case final owner?) owner.drainForDataWipe()
      ]);

  @visibleForTesting
  static void resetWipeGateForTesting() {
    _wipeSuspended = false;
    for (final reference in _owners) {
      final owner = reference.target;
      if (owner == null) continue;
      owner._suspended = false;
      owner._generation++;
    }
  }

  bool _current(int generation, int epoch) =>
      !_suspended &&
      !_wipeSuspended &&
      _allowed() &&
      generation == _generation &&
      epoch == LocalProfileService.instance.epoch;

  void _requireCurrent(int generation, int epoch) {
    if (!_current(generation, epoch)) {
      throw StateError('This wellbeing request is no longer available.');
    }
  }

  /// Whether this session may use the check.
  bool get available => !_suspended && !_wipeSuspended && _allowed();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<List<WellbeingCheckResult>> _read(int generation, int epoch) async {
    if (!_current(generation, epoch)) return [];
    final blob = NeuraPrefsCache.prefs.getString(storageKey);
    if (blob == null) return [];
    final json = await _decrypt(blob);
    if (!_current(generation, epoch)) return [];
    final items = json['results'];
    if (items is! List) return [];
    return items
        .map(WellbeingCheckResult.fromJson)
        .whereType<WellbeingCheckResult>()
        .toList();
  }

  /// Past results, oldest first.
  Future<List<WellbeingCheckResult>> history() {
    final generation = _generation;
    final epoch = LocalProfileService.instance.epoch;
    if (!_current(generation, epoch)) return Future.value([]);
    return _serial(() => _read(generation, epoch));
  }

  /// Saves a finished check. [answers] holds one 0-5 score per question.
  Future<WellbeingCheckResult> record(List<int> answers) {
    final generation = _generation;
    final epoch = LocalProfileService.instance.epoch;
    final admittedAnswers = List<int>.unmodifiable(answers);
    if (!_current(generation, epoch)) {
      return Future.error(StateError('The wellbeing check is unavailable.'));
    }
    return _serial(() async {
      _requireCurrent(generation, epoch);
      if (admittedAnswers.length != questions.length ||
          admittedAnswers.any((score) => score < 0 || score > 5)) {
        throw ArgumentError('Answer every question first.');
      }
      final result = WellbeingCheckResult(
        takenAt: _now(),
        answers: admittedAnswers,
      );
      final results = [...await _read(generation, epoch), result];
      _requireCurrent(generation, epoch);
      while (results.length > maxResults) {
        results.removeAt(0);
      }
      final blob = await _encrypt({
        'results': [for (final item in results) item.toJson()],
      });
      _requireCurrent(generation, epoch);
      final saved = await NeuraPrefsCache.prefs.setString(storageKey, blob);
      _requireCurrent(generation, epoch);
      if (!saved) {
        await NeuraPrefsCache.prefs.reload();
        throw StateError('The check could not be saved on this device.');
      }
      return result;
    });
  }

  /// Whether a check is due: never taken, or the last was [interval] ago.
  Future<bool> isDue() async {
    final generation = _generation;
    final epoch = LocalProfileService.instance.epoch;
    if (!_current(generation, epoch)) return false;
    final results = await history();
    if (!_current(generation, epoch)) return false;
    if (results.isEmpty) return true;
    return !_now().isBefore(results.last.takenAt.add(interval));
  }
}
