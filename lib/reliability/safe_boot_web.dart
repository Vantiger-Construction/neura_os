import 'package:flutter/foundation.dart';

class SafeBoot {
  SafeBoot._();
  static final SafeBoot instance = SafeBoot._();
  final ValueNotifier<bool> safeMode = ValueNotifier(false);
  int get consecutiveFailures => 0;
  Future<void> beginBoot() async {}
  Future<void> completeBoot() async {}
  Future<void> requestSafeMode() async => safeMode.value = true;
  Future<void> clearSafeMode() async => safeMode.value = false;
}
