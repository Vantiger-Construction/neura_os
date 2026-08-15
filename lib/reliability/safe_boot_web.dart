import 'package:flutter/foundation.dart';

class SafeBoot {
  SafeBoot._();
  static final SafeBoot instance = SafeBoot._();
  final ValueNotifier<bool> safeMode = ValueNotifier(false);
  final ValueNotifier<bool> restartRequired = ValueNotifier(false);
  int get consecutiveFailures => 0;
  void preselectSafeModeForProcess() => safeMode.value = true;
  Future<void> beginBoot() async {}
  Future<void> completeBoot() async {}
  Future<void> requestSafeMode() async {
    restartRequired.value = false;
    safeMode.value = true;
  }

  Future<void> clearSafeMode() async {
    if (safeMode.value) restartRequired.value = true;
  }

  Future<void> resetAfterDataWipe() async {
    safeMode.value = true;
    restartRequired.value = true;
  }
}
