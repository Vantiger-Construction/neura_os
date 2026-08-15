import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class SafeBoot {
  SafeBoot._();
  static final SafeBoot instance = SafeBoot._();

  final ValueNotifier<bool> safeMode = ValueNotifier(false);
  File? _stateFile;
  int _consecutiveFailures = 0;
  bool _started = false;

  int get consecutiveFailures => _consecutiveFailures;

  Future<void> beginBoot() async {
    if (_started) return;
    _started = true;
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}${Platform.pathSeparator}neura${Platform.pathSeparator}health');
    await directory.create(recursive: true);
    _stateFile = File('${directory.path}${Platform.pathSeparator}boot-state.json');

    var previousCompleted = true;
    if (await _stateFile!.exists()) {
      try {
        final state = jsonDecode(await _stateFile!.readAsString()) as Map<String, dynamic>;
        previousCompleted = state['completed'] == true;
        _consecutiveFailures = (state['consecutive_failures'] as num?)?.toInt() ?? 0;
      } catch (_) {
        previousCompleted = false;
      }
    }
    _consecutiveFailures = previousCompleted ? 0 : _consecutiveFailures + 1;
    safeMode.value = _consecutiveFailures >= 2;
    await _write(completed: false);
  }

  Future<void> completeBoot() async {
    _consecutiveFailures = 0;
    await _write(completed: true);
  }

  Future<void> requestSafeMode() async {
    safeMode.value = true;
    _consecutiveFailures = 2;
    await _write(completed: false);
  }

  Future<void> clearSafeMode() async {
    safeMode.value = false;
    _consecutiveFailures = 0;
    await _write(completed: true);
  }

  Future<void> _write({required bool completed}) async {
    await _stateFile?.writeAsString(jsonEncode({
      'v': 1,
      'completed': completed,
      'safe_mode': safeMode.value,
      'consecutive_failures': _consecutiveFailures,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }), flush: true);
  }
}
