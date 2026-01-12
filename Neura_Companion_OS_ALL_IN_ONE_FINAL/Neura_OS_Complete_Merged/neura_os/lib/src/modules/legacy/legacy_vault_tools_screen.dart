import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

import 'legacy_vault_service.dart';

class LegacyVaultToolsScreen extends StatefulWidget {
  const LegacyVaultToolsScreen({super.key});

  @override
  State<LegacyVaultToolsScreen> createState() => _LegacyVaultToolsScreenState();
}

class _LegacyVaultToolsScreenState extends State<LegacyVaultToolsScreen> {
  bool _busy = false;

  Future<String?> _promptPassphrase({required String title}) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Passphrase'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Continue')),
        ],
      ),
    );
  }

  Future<void> _exportVault() async {
    setState(() => _busy = true);
    try {
      final file = await LegacyVaultService.instance.exportVaultZip();
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Neura Companion — Legacy Vault Backup\nKeep this file safe.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup share sheet opened.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportVaultDecrypted() async {
    final pass = await _promptPassphrase(title: 'Passphrase to decrypt encrypted capsules');
    if (pass == null || pass.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final file = await LegacyVaultService.instance.exportVaultZip(
        decryptEncrypted: true,
        passphrase: pass,
      );
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Neura Companion — Legacy Vault Backup (decrypted)\nTreat as sensitive.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Decrypted backup share sheet opened.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Decrypted export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importVault() async {
    setState(() => _busy = true);
    try {
      final count = await LegacyVaultService.instance.importVaultZipInteractive();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported $count capsules.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vault Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Backups are local'),
            subtitle: Text('Neura stores your Legacy Vault on this device. Export backups if you want a copy elsewhere.'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Export backup (recommended)'),
            subtitle: const Text('Creates a ZIP of your Legacy Vault. Encrypted capsules stay encrypted.'),
            onTap: _busy ? null : _exportVault,
          ),
          ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: const Text('Export decrypted backup (dangerous)'),
            subtitle: const Text('Decrypts encrypted capsules into plaintext inside the ZIP. Use only if you must.'),
            onTap: _busy ? null : _exportVaultDecrypted,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.unarchive_outlined),
            title: const Text('Import backup'),
            subtitle: const Text('Merges a previously exported ZIP into your current vault.'),
            onTap: _busy ? null : _importVault,
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
