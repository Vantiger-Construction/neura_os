import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../reliability/safe_boot.dart';
import '../services/auth_service.dart';
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
                onPressed:
                    readiness.canSync && !_syncing ? _startSync : null,
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
            ],
          ),
        );
      },
    );
  }
}
