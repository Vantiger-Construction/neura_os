import '../modules/vault/memory_vault_models.dart';

/// Narrow read boundary for backup code, implemented by [MemoryVaultStore].
///
/// Exists only so backup logic (export, scheduled backup, verification) can
/// be unit tested against a fake without needing the vault's PIN-derived
/// encryption or OS secure storage.
abstract interface class VaultItemSource {
  Future<List<VaultItem>> getItems({required String pin});

  /// Recheck [mayWrite] after queued work and immediately before persisting.
  /// A write already admitted to the platform must be drained by wipe.
  Future<int> importItems({
    required String pin,
    required List<VaultItem> imported,
    required bool Function() mayWrite,
  });
}
