import 'package:flutter/material.dart';

import '../core/app_log.dart';
import 'memory_vault_store.dart';

/// In-memory PIN cache. We ask once per app session (not stored on disk).
class VaultSession {
  VaultSession._();

  static String? _pin;

  static String? get sessionPin => _pin;

  static void lock() {
    _pin = null;
  }

  static Future<bool> ensureUnlocked(BuildContext context) async {
    // If we already unlocked this session, we are good.
    if (_pin != null && _pin!.trim().isNotEmpty) return true;

    final store = MemoryVaultStore.instance;

    // If not configured yet, ask the user to create a PIN.
    final hasPin = await store.hasPinConfigured();
    if (!context.mounted) return false;

    if (!hasPin) {
      final created = await _promptCreatePin(context);
      if (created == null) return false;
      await store.configurePin(created);
      _pin = created;
      await AppLog.instance.info('vault_event', {'msg': 'Vault PIN configured (verifier stored).'});
      return true;
    }

    // Already configured: ask for PIN to unlock.
    for (var attempt = 0; attempt < 3; attempt++) {
      final entered = await _promptEnterPin(context);
      if (entered == null) return false;
      final ok = await store.validatePin(entered);
      if (ok) {
        _pin = entered;
        return true;
      }
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nope. That PIN did not match.')),
      );
    }

    return false;
  }

  static Future<String?> _promptEnterPin(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Unlock Memory Vault'),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'PIN',
              hintText: 'Enter your vault PIN',
            ),
            autofocus: true,
            onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Unlock')),
          ],
        );
      },
    );
  }

  static Future<String?> _promptCreatePin(BuildContext context) async {
    final a = TextEditingController();
    final b = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Create a Vault PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This PIN is never stored. You will enter it once per session to unlock the vault.'),
              const SizedBox(height: 12),
              TextField(
                controller: a,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'PIN'),
              ),
              TextField(
                controller: b,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Confirm PIN'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final p1 = a.text.trim();
                final p2 = b.text.trim();
                if (p1.length < 4 || p1 != p2) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('PINs must match and be at least 4 digits.')),
                  );
                  return;
                }
                Navigator.of(ctx).pop(p1);
              },
              child: const Text('Set PIN'),
            ),
          ],
        );
      },
    );
  }
}
