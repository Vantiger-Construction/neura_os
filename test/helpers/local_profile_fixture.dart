import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/profiles/local_profile_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

/// Models a registry committed by the earlier release on disposable storage.
/// Production activation stays held; tests do not get a service bypass.
Future<void> seedExistingLocalProfileRegistry(
    {bool withSentinel = true}) async {
  final crypto = await MemoryCrypto.demo();
  crypto.requireOsBackedKey();
  final encrypted = await crypto.encryptJson({'version': 1, 'profiles': []});
  final prefs = NeuraPrefsCache.prefs;
  expect(
      await prefs.setString(LocalProfileService.storageKey, encrypted), isTrue);
  if (withSentinel) {
    expect(await prefs.setBool(LocalProfileService.modeKey, true), isTrue);
  }
  await prefs.reload();
}
