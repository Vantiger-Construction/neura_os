import '../neura_fault_event.dart';

/// Web-safe stub. (No dart:io on web)
class NeuraErrorVault {
  static Future<void> append(NeuraFaultEvent event) async {
    // no-op on web
  }

  static Future<String?> getVaultPath() async => null;

  static Future<List<String>> tail({int maxLines = 200}) async =>
      const <String>[];

  static Future<void> clear() async {}

  static Future<String> exportCopy() {
    throw UnsupportedError(
      'Crash-vault export is unavailable in the browser build.',
    );
  }

  static Future<void> suspendForDataWipe() async {}
}
