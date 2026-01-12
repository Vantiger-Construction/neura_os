import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../modules/legacy/legacy_vault_service.dart';

class NeuraDataWipeService {
  /// Delete **all** locally stored app data we know about.
  ///
  /// This is intentionally conservative: it clears SharedPreferences and deletes the Legacy Vault folder.
  static Future<void> wipeAllLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    await wipeLegacyVault();
  }

  static Future<void> wipeLegacyVault() async {
    final vaultDir = await LegacyVaultService.instance.vaultDirectory();
    if (await vaultDir.exists()) {
      await vaultDir.delete(recursive: true);
    }

    // Defensive: some platforms can leave empty parent folders.
    try {
      final parent = Directory(vaultDir.path);
      if (await parent.exists() && parent.listSync().isEmpty) {
        await parent.delete();
      }
    } catch (_) {
      // ignore
    }
  }
}
