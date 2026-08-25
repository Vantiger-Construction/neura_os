import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class SafeBoot {
  SafeBoot._();
  static final SafeBoot instance = SafeBoot._();

  final ValueNotifier<bool> safeMode = ValueNotifier(false);
  final ValueNotifier<bool> restartRequired = ValueNotifier(false);
  File? _stateFile;
  int _consecutiveFailures = 0;
  bool _started = false;
  bool _preselectedForProcess = false;

  int get consecutiveFailures => _consecutiveFailures;

  /// Latches Safe Mode before asynchronous boot-state loading starts.
  /// Recovery UI uses this so [beginBoot] cannot overwrite the user's choice.
  void preselectSafeModeForProcess() {
    _preselectedForProcess = true;
    safeMode.value = true;
  }

  Future<void> beginBoot() async {
    if (_started) return;
    restartRequired.value = false;
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}neura'
      '${Platform.pathSeparator}health',
    );
    await directory.create(recursive: true);
    _stateFile = File(
      '${directory.path}${Platform.pathSeparator}boot-state.json',
    );

    var previousCompleted = true;
    if (await _stateFile!.exists()) {
      try {
        final state = jsonDecode(await _stateFile!.readAsString())
            as Map<String, dynamic>;
        previousCompleted = state['completed'] == true;
        _consecutiveFailures =
            (state['consecutive_failures'] as num?)?.toInt() ?? 0;
      } catch (_) {
        previousCompleted = false;
      }
    }
    _consecutiveFailures = previousCompleted ? 0 : _consecutiveFailures + 1;
    if (_preselectedForProcess && _consecutiveFailures < 2) {
      _consecutiveFailures = 2;
    }
    safeMode.value = _preselectedForProcess || _consecutiveFailures >= 2;
    await _write(completed: false);
    _started = true;
  }

  Future<void> completeBoot() async {
    _consecutiveFailures = 0;
    await _write(completed: true);
  }

  Future<void> requestSafeMode() async {
    _preselectedForProcess = true;
    restartRequired.value = false;
    safeMode.value = true;
    _consecutiveFailures = 2;
    await _write(completed: false);
  }

  Future<void> clearSafeMode() async {
    _consecutiveFailures = 0;
    if (safeMode.value) {
      // Native/audio services are intentionally not reactivated inside the
      // current process. Persist a clean next launch while keeping this
      // session safely latched.
      restartRequired.value = true;
    }
    await _write(completed: true, persistedSafeMode: false);
  }

  /// Drops the cached health-file path after the app-support tree is wiped.
  Future<void> resetAfterDataWipe() async {
    _stateFile = null;
    _consecutiveFailures = 0;
    _started = false;
    _preselectedForProcess = true;
    safeMode.value = true;
    restartRequired.value = true;
  }

  Future<void> _write({
    required bool completed,
    bool? persistedSafeMode,
  }) async {
    await _stateFile?.writeAsString(
      jsonEncode({
        'v': 1,
        'completed': completed,
        'safe_mode': persistedSafeMode ?? safeMode.value,
        'consecutive_failures': _consecutiveFailures,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }
}
