import 'package:flutter/foundation.dart';

import '../../modules/core/app_log.dart';

class SelfHealService {
  SelfHealService._internal();
  static final SelfHealService instance = SelfHealService._internal();

  final List<_ErrorRecord> _log = [];

  List<Map<String, String>> get errorLog => _log
      .map((r) => {
            'where': r.where,
            'error': r.error,
            'time': r.time.toIso8601String(),
          })
      .toList();

  Future<void> recordError(String where, Object error, StackTrace st) async {
    final record = _ErrorRecord(
      where: where,
      error: '${error.runtimeType} details withheld',
      time: DateTime.now(),
    );
    _log.add(record);
    await AppLog.instance.caught(
      'self_heal_recorded',
      error,
      st,
      context: <String, Object?>{'where': where},
    );
    if (kDebugMode) {
      debugPrint('[SelfHeal] $where — ${error.runtimeType}');
      debugPrintStack(stackTrace: st, maxFrames: 10);
    }
  }

  void clearLog() => _log.clear();
}

class _ErrorRecord {
  final String where;
  final String error;
  final DateTime time;
  const _ErrorRecord({
    required this.where,
    required this.error,
    required this.time,
  });
}
