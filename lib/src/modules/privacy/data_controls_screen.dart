import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/data_wipe_service.dart';
import '../legacy/legacy_vault_service.dart';

class DataControlsScreen extends StatefulWidget {
  const DataControlsScreen({super.key});

  @override
  State<DataControlsScreen> createState() => _DataControlsScreenState();
}

class _DataControlsScreenState extends State<DataControlsScreen> {
  bool _busy = false;

  Future<String?> _promptPassphrase(String title) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Passphrase'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<bool> _confirm(String title, String message) async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Do it'),
              ),
            ],
          ),
        )) ??
        false;
  }

  Future<void> _exportLegacyVault({required bool decrypt}) async {
    setState(() => _busy = true);
    try {
      String? pass;
      if (decrypt) {
        pass = await _promptPassphrase('Passphrase (used for all encrypted capsules)');
        if (pass == null || pass.trim().isEmpty) return;
      }

      final zip = await LegacyVaultService.instance.exportVaultZip(
        passphrase: pass,
        decryptEncrypted: decrypt,
      );

      await Share.shareXFiles(
        [XFile(zip.path)],
        text: decrypt
            ? 'Neura Legacy Vault export (decrypted)'
            : 'Neura Legacy Vault export (raw)',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importLegacyVault() async {
    setState(() => _busy = true);
    try {
      final n = await LegacyVaultService.instance.importVaultZipInteractive();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Imported $n capsule(s).')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteLegacyVault() async {
    final ok = await _confirm(
      'Delete Legacy Vault?',
      'This permanently deletes all capsules and attachments stored on this device.',
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      await NeuraDataWipeService.wipeLegacyVault();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Legacy Vault deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _wipeAllLocal() async {
    final ok = await _confirm(
      'Wipe all local data?',
      'This removes Neura credentials, encryption keys, settings, memories, '
          'journals, recordings, logs, and app-generated exports from this '
          'device. Copies you already shared outside Neura are not affected. '
          'This cannot be undone.',
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      await NeuraDataWipeService.wipeAllLocalData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All local data wiped. Restart Neura before continuing.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(
        content: Text(
          'Wipe incomplete: $e Restart Neura before retrying.',
        ),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data Controls')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Your data is yours. These tools let you export or delete what\'s stored on this device.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Export Legacy Vault (.zip) — raw'),
                  subtitle: const Text('Keeps encrypted capsules encrypted.'),
                  leading: const Icon(Icons.archive_outlined),
                  onTap: _busy ? null : () => _exportLegacyVault(decrypt: false),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Export Legacy Vault (.zip) — decrypted'),
                  subtitle: const Text('Requires passphrase; assumes shared passphrase.'),
                  leading: const Icon(Icons.lock_open),
                  onTap: _busy ? null : () => _exportLegacyVault(decrypt: true),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Import Legacy Vault (.zip)'),
                  subtitle: const Text('Adds capsules; never overwrites existing IDs.'),
                  leading: const Icon(Icons.unarchive_outlined),
                  onTap: _busy ? null : _importLegacyVault,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Delete Legacy Vault from this device'),
                  leading: const Icon(Icons.delete_outline),
                  onTap: _busy ? null : _deleteLegacyVault,
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Wipe ALL local data'),
                  subtitle: const Text(
                    'Removes credentials and every known app-owned local record.',
                  ),
                  leading: const Icon(Icons.warning_amber_rounded),
                  onTap: _busy ? null : _wipeAllLocal,
                ),
              ],
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ]
        ],
      ),
    );
  }
}
