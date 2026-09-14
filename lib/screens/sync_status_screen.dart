import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../reliability/safe_boot.dart';
import '../services/auth_service.dart';
import '../services/conflict_resolution_service.dart';
import '../services/sync_conflict_log.dart';
import '../services/sync_readiness.dart';
import '../services/sync_service.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  final _sync = SyncService();
  bool _syncing = false;
  DateTime? _lastAttempt;
  List<SyncConflictRecord> _conflicts = const [];

  @override
  void initState() {
    super.initState();
    _loadConflicts();
  }

  Future<void> _loadConflicts() async {
    await SyncConflictLog.instance.load();
    if (!mounted) return;
    setState(() => _conflicts = SyncConflictLog.instance.records);
  }

  Future<void> _startSync() async {
    final readiness = _readiness();
    if (!readiness.canSync || _syncing) return;

    setState(() => _syncing = true);
    await _sync.syncAll();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _lastAttempt = DateTime.now();
    });
    await _loadConflicts();
  }

  Future<void> _confirmClearConflicts() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear resolved conflicts?'),
        content: const Text(
          'This clears the local record of past conflict resolutions. It '
          'does not change any journal entry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SyncConflictLog.instance.clear();
      await _loadConflicts();
    }
  }

  static String _winnerLabel(ConflictWinner winner) => switch (winner) {
        ConflictWinner.local => 'This device kept its version',
        ConflictWinner.remote => 'The cloud version was kept',
        ConflictWinner.equivalent => 'Both versions matched',
      };

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} $hour:$minute';
  }

  SyncReadiness _readiness() {
    return evaluateSyncReadiness(
      configured: SupabaseConfig.isConfigured,
      safeMode: SafeBoot.instance.safeMode.value,
      clientAvailable: AuthService.isAvailable,
    );
  }

  IconData _iconFor(SyncReadinessState state) {
    return switch (state) {
      SyncReadinessState.ready => Icons.cloud_done_outlined,
      SyncReadinessState.safeMode => Icons.shield_outlined,
      SyncReadinessState.notConfigured => Icons.phonelink_off_outlined,
      SyncReadinessState.clientUnavailable => Icons.cloud_off_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SafeBoot.instance.safeMode,
      builder: (context, _, __) {
        final readiness = _readiness();
        return Scaffold(
          appBar: AppBar(title: const Text('Sync & Reliability')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(_iconFor(readiness.state)),
                  title: Text(readiness.title),
                  subtitle: Text(readiness.detail),
                ),
              ),
              const SizedBox(height: 12),
              const Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.storage_outlined),
                      title: Text('Local journal'),
                      subtitle: Text(
                        'Primary copy stays available without an account or network.',
                      ),
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.lock_outline),
                      title: Text('Ownership boundary'),
                      subtitle: Text(
                        'Cloud rows remain restricted to the signed-in user.',
                      ),
                    ),
                    Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.health_and_safety_outlined),
                      title: Text('Failure behavior'),
                      subtitle: Text(
                        'Cloud failures are logged and do not block local journaling.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: readiness.canSync && !_syncing ? _startSync : null,
                icon: _syncing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(_syncing ? 'Syncing…' : 'Sync now'),
              ),
              if (_lastAttempt != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Last requested: ${_lastAttempt!.toLocal()}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Resolved conflicts',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (_conflicts.isNotEmpty)
                    TextButton(
                      onPressed: _confirmClearConflicts,
                      child: const Text('Clear'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (_conflicts.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.rule_outlined),
                    title: Text('No conflicts resolved yet'),
                    subtitle: Text(
                      'If a journal entry changes on two devices before '
                      'syncing, the resolution will be listed here.',
                    ),
                  ),
                )
              else
                ..._conflicts.map(
                  (conflict) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.merge_type),
                      title: Text(_winnerLabel(conflict.winner)),
                      subtitle: Text(
                        'Local: ${_formatDateTime(conflict.localUpdatedAt)} • '
                        'Cloud: ${_formatDateTime(conflict.remoteUpdatedAt)}\n'
                        'Resolved ${_formatDateTime(conflict.resolvedAt)}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
