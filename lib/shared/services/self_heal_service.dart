import 'package:flutter/foundation.dart';

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
      error: error.toString(),
      time: DateTime.now(),
    );
    _log.add(record);
    if (kDebugMode) {
      debugPrint('[SelfHeal] $where — $error');
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
