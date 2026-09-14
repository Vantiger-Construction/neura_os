import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/portable_vault_backup_service.dart';
import '../../services/scheduled_backup_settings.dart';
import '../../widgets/neura_explain.dart';
import 'memory_vault_models.dart';
import 'memory_vault_store.dart';
import 'vault_session.dart';

class MemoryVaultScreen extends StatefulWidget {
  const MemoryVaultScreen({super.key});

  @override
  State<MemoryVaultScreen> createState() => _MemoryVaultScreenState();
}

class _MemoryVaultScreenState extends State<MemoryVaultScreen> {
  bool _loading = true;
  List<VaultItem> _items = const [];
  final _backup = PortableVaultBackupService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ok = await VaultSession.ensureUnlocked(context);
    if (!mounted) return;
    if (!ok) {
      setState(() => _loading = false);
      return;
    }
    final pin = VaultSession.sessionPin!;
    final items = await MemoryVaultStore.instance.getItems(pin: pin);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _addItem() async {
    final pin = VaultSession.sessionPin;
    if (pin == null) {
      await _load();
      return;
    }

    final title = TextEditingController();
    final body = TextEditingController();
    final tags = TextEditingController();
    String titleValue = '';
    String bodyValue = '';
    String tagsValue = '';
    bool? ok;

    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('New Vault Entry'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Title')),
                  TextField(
                    controller: body,
                    decoration: const InputDecoration(labelText: 'Body'),
                    minLines: 3,
                    maxLines: 6,
                  ),
                  TextField(
                    controller: tags,
                    decoration: const InputDecoration(
                        labelText: 'Tags (comma separated)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Save')),
            ],
          );
        },
      );
      if (ok == true) {
        titleValue = title.text.trim();
        bodyValue = body.text.trim();
        tagsValue = tags.text;
      }
    } finally {
      title.dispose();
      body.dispose();
      tags.dispose();
    }

    if (ok != true) return;
    await MemoryVaultStore.instance.add(
      pin: pin,
      title: titleValue.isEmpty ? 'Untitled' : titleValue,
      body: bodyValue,
      tags: tagsValue
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(),
    );

    if (!mounted) return;
    await _load();
  }

  Future<void> _delete(String id) async {
    final pin = VaultSession.sessionPin;
    if (pin == null) {
      await _load();
      return;
    }
    await MemoryVaultStore.instance.delete(pin: pin, id: id);
    if (!mounted) return;
    await _load();
  }

  Future<String?> _requestBackupPassphrase({
    required String title,
    required bool confirm,
  }) async {
    var passphrase = '';
    var confirmation = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Backup passphrase',
                helperText: 'At least 12 characters',
              ),
              onChanged: (value) => passphrase = value,
            ),
            if (confirm)
              TextField(
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm passphrase',
                ),
                onChanged: (value) => confirmation = value,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (passphrase.length < 12 ||
                  (confirm && passphrase != confirmation)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Use at least 12 matching characters.',
                    ),
                  ),
                );
                return;
              }
              Navigator.of(dialogContext).pop(passphrase);
            },
            child: Text(confirm ? 'Export' : 'Import'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup() async {
    if (VaultSession.sessionPin == null) {
      await _load();
      if (!mounted || VaultSession.sessionPin == null) return;
    }
    final passphrase = await _requestBackupPassphrase(
      title: 'Export encrypted backup',
      confirm: true,
    );
    if (!mounted || passphrase == null) return;

    try {
      final path = await _backup.exportToFile(
        pin: VaultSession.sessionPin!,
        passphrase: passphrase,
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encrypted backup exported.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup export failed safely.')),
      );
    }
  }

  Future<void> _importBackup() async {
    if (VaultSession.sessionPin == null) {
      await _load();
      if (!mounted || VaultSession.sessionPin == null) return;
    }
    final passphrase = await _requestBackupPassphrase(
      title: 'Import encrypted backup',
      confirm: false,
    );
    if (!mounted || passphrase == null) return;

    try {
      final count = await _backup.importFromFile(
        pin: VaultSession.sessionPin!,
        passphrase: passphrase,
      );
      if (!mounted || count == null) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $count vault entries.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup rejected. Check the file and passphrase.'),
        ),
      );
    }
  }

  Future<void> _openScheduledBackupSettings() async {
    if (VaultSession.sessionPin == null) {
      await _load();
      if (!mounted || VaultSession.sessionPin == null) return;
    }
    final settings = ScheduledBackupSettings.instance;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> toggle(bool value) async {
            if (value) {
              final passphrase = await _requestBackupPassphrase(
                title: 'Set an automatic-backup passphrase',
                confirm: true,
              );
              if (passphrase == null) return;
              await settings.enable(passphrase);
            } else {
              await settings.disable();
            }
            setDialogState(() {});
          }

          Future<void> backUpNow() async {
            final pin = VaultSession.sessionPin;
            if (pin == null) return;
            final result = await _backup.runScheduledBackupIfDue(
              pin: pin,
              interval: Duration.zero,
            );
            setDialogState(() {});
            if (!mounted) return;
            final message = switch (result.status) {
              ScheduledBackupStatus.succeeded =>
                'Backed up ${result.itemCount ?? 0} entries.',
              ScheduledBackupStatus.failed => 'Backup failed: ${result.reason}',
              ScheduledBackupStatus.skipped => 'Skipped: ${result.reason}',
            };
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }

          final lastRun = settings.lastRunAt;
          final lastOutcome = settings.lastOutcome;
          final lastError = settings.lastError;

          return AlertDialog(
            title: const Text('Automatic backups'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'When on, Neura backs up your vault locally (not to the '
                  'cloud) each time you unlock it, at most once a day. The '
                  'backup is verified before it replaces the previous one.',
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.enabled,
                  onChanged: (value) => unawaited(toggle(value)),
                  title: const Text('Enabled'),
                ),
                if (settings.enabled) ...[
                  const SizedBox(height: 4),
                  Text(
                    lastRun == null
                        ? 'No automatic backup has run yet.'
                        : 'Last run: ${lastRun.toLocal()} • '
                            '${lastOutcome == ScheduledBackupOutcome.success ? 'succeeded' : 'failed'}'
                            '${lastOutcome == ScheduledBackupOutcome.failed && lastError != null ? ' ($lastError)' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => unawaited(backUpNow()),
                    child: const Text('Back up now'),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _wipe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wipe Vault'),
        content: const Text(
            'This permanently removes all vault entries and the PIN verifier.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Wipe')),
        ],
      ),
    );
    if (ok != true) return;

    await MemoryVaultStore.instance.wipe();
    VaultSession.lock();
    if (!mounted) return;
    setState(() {
      _items = const [];
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory Vault'),
        actions: [
          IconButton(
            tooltip: 'Export encrypted backup',
            onPressed: _exportBackup,
            icon: const Icon(Icons.file_upload_outlined),
          ),
          IconButton(
            tooltip: 'Import encrypted backup',
            onPressed: _importBackup,
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: 'Automatic backups',
            onPressed: _openScheduledBackupSettings,
            icon: const Icon(Icons.schedule_outlined),
          ),
          IconButton(
            tooltip: 'Explain',
            onPressed: () => NeuraExplain.show(
              context,
              title: 'Memory Vault',
              body:
                  'Encrypted notes for the stuff that matters.\n\nSecurity: Your PIN is never stored. You enter it once per app session to unlock the vault.',
            ),
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: 'Lock',
            onPressed: () {
              VaultSession.lock();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Vault locked for this session.')),
              );
            },
            icon: const Icon(Icons.lock_outline),
          ),
          IconButton(
            tooltip: 'Wipe',
            onPressed: _wipe,
            icon: const Icon(Icons.delete_forever_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addItem,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No vault entries yet.'))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final it = _items[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: ListTile(
                        title: Text(it.title),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            Text(it.body),
                            if (it.tags.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: it.tags
                                    .map((t) => Chip(
                                        label: Text(t),
                                        visualDensity: VisualDensity.compact))
                                    .toList(),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              '${it.createdAt.toLocal()}'.split('.').first,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(it.id),
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
    );
  }
}
