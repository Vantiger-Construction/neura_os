import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../modules/coach/coach_store.dart';
import '../../../modules/core/app_log.dart';
import '../../../modules/mood/mood_store.dart';
import '../../../modules/pay_it_forward/goodwill_store.dart';
import '../../../modules/quests/quest_store.dart';
import '../../../modules/review/weekly_review_store.dart';
import '../../../modules/timeline/life_timeline_service.dart';
import '../../core/data_wipe_service.dart';
import '../legacy/legacy_vault_service.dart';

class DataControlsScreen extends StatefulWidget {
  const DataControlsScreen({super.key});

  @override
  State<DataControlsScreen> createState() => _DataControlsScreenState();
}

class _DataControlsScreenState extends State<DataControlsScreen> {
  bool _busy = false;

  Future<void> _exportLifeData() async {
    setState(() => _busy = true);
    try {
      // Build a friendly, unified export. No remote calls. Everything is local.
      final moods = await MoodStore.instance.getAll();
      final kindness = await GoodwillStore.instance.getAll();
      final quests = await QuestStore.instance.getQuests();
      final done = await QuestStore.instance.getDone();
      final reviews = await WeeklyReviewStore.instance.getAll();
      final coach = await CoachStore.instance.getAll();
      final timeline = await LifeTimelineService.instance.build();

      final payload = {
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'schema': 'neura_life_export_v1',
        'counts': {
          'moods': moods.length,
          'kindness': kindness.length,
          'quests': quests.length,
          'questDone': done.length,
          'weeklyReviews': reviews.length,
          'coachNotes': coach.length,
          'timelineEvents': timeline.length,
        },
        'mood': moods.map((m) => m.toJson()).toList(growable: false),
        'kindness': kindness.map((k) => k.toJson()).toList(growable: false),
        'quests': quests.map((q) => q.toJson()).toList(growable: false),
        'questDone': done.map((d) => d.toJson()).toList(growable: false),
        'weeklyReviews': reviews.map((r) => r.toJson()).toList(growable: false),
        'coachNotes': coach.map((c) => c.toJson()).toList(growable: false),
        'timeline': timeline.map((e) => e.toJson()).toList(growable: false),
      };

      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/neura_life_export_$ts.json');
      await file
          .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Neura Life Data Export',
        text: 'Your Neura life data export (stored on-device).',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Life export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportAppLogTail() async {
    setState(() => _busy = true);
    try {
      final lines = await AppLog.instance.tail(maxLines: 300);
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/neura_app_log_tail_$ts.ndjson');
      await file.writeAsString(lines.join('\n'));
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/x-ndjson')],
        subject: 'Neura App Log Tail',
        text: 'Recent Neura logs (last ~300 entries).',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Log export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAppLog() async {
    final ok = await _confirm('Clear app log?',
        'This deletes the local diagnostic log file on this device.');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await AppLog.instance.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('App log cleared.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Clear log failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptPassphrase(String title) async {
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
        pass = await _promptPassphrase(
            'Passphrase (used for all encrypted capsules)');
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
      'This clears app settings + deletes the Legacy Vault. This cannot be undone.',
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      await NeuraDataWipeService.wipeAllLocalData();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('All local data wiped.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Wipe failed: $e')));
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
                  title: const Text('Export Life Data (.json)'),
                  subtitle: const Text(
                      'Moods, quests, kindness, weekly reviews, coach notes + timeline.'),
                  leading: const Icon(Icons.download_outlined),
                  onTap: _busy ? null : _exportLifeData,
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Export App Log Tail (.ndjson)'),
                  subtitle: const Text(
                      'Last ~300 diagnostic events (handy for bug reports).'),
                  leading: const Icon(Icons.receipt_long_outlined),
                  onTap: _busy ? null : _exportAppLogTail,
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Clear App Log'),
                  subtitle:
                      const Text('Deletes the local diagnostic log file.'),
                  leading: const Icon(Icons.delete_sweep_outlined),
                  onTap: _busy ? null : _clearAppLog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Export Legacy Vault (.zip) — raw'),
                  subtitle: const Text('Keeps encrypted capsules encrypted.'),
                  leading: const Icon(Icons.archive_outlined),
                  onTap:
                      _busy ? null : () => _exportLegacyVault(decrypt: false),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Export Legacy Vault (.zip) — decrypted'),
                  subtitle: const Text(
                      'Requires passphrase; assumes shared passphrase.'),
                  leading: const Icon(Icons.lock_open),
                  onTap: _busy ? null : () => _exportLegacyVault(decrypt: true),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Import Legacy Vault (.zip)'),
                  subtitle: const Text(
                      'Adds capsules; never overwrites existing IDs.'),
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
                  subtitle:
                      const Text('Clears settings and deletes Legacy Vault.'),
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
