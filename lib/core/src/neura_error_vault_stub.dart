import '../neura_fault_event.dart';

/// Web-safe stub. (No dart:io on web)
class NeuraErrorVault {
  static Future<void> append(NeuraFaultEvent event) async {
    // no-op on web
  }

  static Future<String?> getVaultPath() async => null;

  static Future<void> suspendForDataWipe() async {}
}
