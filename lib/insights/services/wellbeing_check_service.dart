import 'dart:async';

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
    final scores = answers.whereType<int>().toList();
    if (scores.length != WellbeingCheckService.questions.length) return null;
    if (scores.any((score) => score < 0 || score > 5)) return null;
    return WellbeingCheckResult(takenAt: taken, answers: scores);
  }
}

/// How a score reads. Not a diagnosis: a prompt to notice and, when it is
/// low, to talk with someone.
enum WellbeingBand {
  /// 0-28: a hard stretch.
  low,

  /// 29-50: lower than people usually report.
  reduced,

  /// 51-100: in the range most people report.
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
class WellbeingCheckService {
  WellbeingCheckService({
    Future<String> Function(Map<String, dynamic>)? encrypt,
    Future<Map<String, dynamic>> Function(String)? decrypt,
    DateTime Function()? now,
    bool Function()? allowed,
  })  : _encrypt = encrypt ??
            ((json) async => (await MemoryCrypto.demo()).encryptJson(json)),
        _decrypt = decrypt ??
            ((blob) async => (await MemoryCrypto.demo()).decryptJson(blob)),
        _now = now ?? DateTime.now,
        _allowed = allowed ?? (() => !LocalProfileService.instance.enabled);

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

  /// Whether this session may use the check.
  bool get available => _allowed();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<List<WellbeingCheckResult>> _read() async {
    if (!_allowed()) return [];
    final blob = NeuraPrefsCache.prefs.getString(storageKey);
    if (blob == null) return [];
    final json = await _decrypt(blob);
    final items = json['results'];
    if (items is! List) return [];
    return items
        .map(WellbeingCheckResult.fromJson)
        .whereType<WellbeingCheckResult>()
        .toList();
  }

  /// Past results, oldest first.
  Future<List<WellbeingCheckResult>> history() => _serial(_read);

  /// Saves a finished check. [answers] holds one 0-5 score per question.
  Future<WellbeingCheckResult> record(List<int> answers) => _serial(() async {
        if (!_allowed()) {
          throw StateError('The wellbeing check is not available here.');
        }
        if (answers.length != questions.length ||
            answers.any((score) => score < 0 || score > 5)) {
          throw ArgumentError('Answer every question first.');
        }
        final result = WellbeingCheckResult(
          takenAt: _now(),
          answers: List<int>.unmodifiable(answers),
        );
        final results = [...await _read(), result];
        while (results.length > maxResults) {
          results.removeAt(0);
        }
        final blob = await _encrypt({
          'results': [for (final item in results) item.toJson()],
        });
        if (!await NeuraPrefsCache.prefs.setString(storageKey, blob)) {
          throw StateError('The check could not be saved on this device.');
        }
        return result;
      });

  /// Whether a check is due: never taken, or the last was [interval] ago.
  Future<bool> isDue() async {
    if (!_allowed()) return false;
    final results = await history();
    if (results.isEmpty) return true;
    return !_now().isBefore(results.last.takenAt.add(interval));
  }
}
