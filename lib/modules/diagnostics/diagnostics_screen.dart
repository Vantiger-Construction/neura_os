import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/neura_error_vault.dart';
import '../../intelligence/intelligence_center_screen.dart';
import '../../reliability/module_health_monitor.dart';
import '../../reliability/safe_boot.dart';
import '../../reliability/timeline_vault.dart';
import '../../startup/neura_bootstrap_log.dart';
import '../core/app_log.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<String> _lines = const [];
  List<String> _crashes = const [];
  List<Map<String, Object?>> _bootstrapErrors = const [];
  List<Map<String, dynamic>> _timeline = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        AppLog.instance.tail(maxLines: 250),
        TimelineVault.instance.tail(maxLines: 50),
        NeuraErrorVault.tail(maxLines: 100),
        NeuraBootstrapLog.tail(maxRecords: 100),
      ]);
      if (!mounted) return;
      setState(() {
        _lines = results[0] as List<String>;
        _timeline = results[1] as List<Map<String, dynamic>>;
        _crashes = results[2] as List<String>;
        _bootstrapErrors = results[3] as List<Map<String, Object?>>;
        _loading = false;
      });
    } catch (error, stack) {
      await AppLog.instance.caught(
        'diagnostics_load_failed',
        error,
        stack,
      );
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _exportTimeline() async {
    try {
      final path = await TimelineVault.instance.exportCopy();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Timeline exported to $path')),
      );
    } catch (error, stack) {
      await AppLog.instance.exception(
        'diagnostics_timeline_export_failed',
        error,
        stack,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timeline export failed. See logs.')),
      );
    }
  }

  Future<void> _exportAppLog() async {
    try {
      final path = await AppLog.instance.exportCopy();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Application log exported to $path')),
      );
    } catch (error, stack) {
      await AppLog.instance.exception(
        'diagnostics_log_export_failed',
        error,
        stack,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Log export is unavailable on this platform.'),
        ),
      );
    }
  }

  Future<void> _exportCrashLogs() async {
    try {
      final paths = <String>[];
      if (_crashes.isNotEmpty) {
        paths.add(await NeuraErrorVault.exportCopy());
      }
      final bootstrapPath = await NeuraBootstrapLog.exportCopy();
      if (bootstrapPath != null) paths.add(bootstrapPath);
      if (paths.isEmpty) throw StateError('The crash logs are empty.');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Crash diagnostics exported to ${paths.join(' · ')}',
          ),
        ),
      );
    } catch (error, stack) {
      await AppLog.instance.exception(
        'diagnostics_crash_export_failed',
        error,
        stack,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no crash records to export.')),
      );
    }
  }

  Future<void> _toggleSafeMode() async {
    if (SafeBoot.instance.safeMode.value) {
      if (SafeBoot.instance.restartRequired.value) return;
      await SafeBoot.instance.clearSafeMode();
    } else {
      await SafeBoot.instance.requestSafeMode();
    }
    if (!mounted) return;
    final message = SafeBoot.instance.restartRequired.value
        ? 'Safe Mode stays active until you restart Neura.'
        : 'Safe Mode is active for this session.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _clear() async {
    try {
      await Future.wait<void>([
        AppLog.instance.clear(),
        NeuraErrorVault.clear(),
        NeuraBootstrapLog.clear(),
      ]);
    } catch (error, stack) {
      await AppLog.instance.exception(
        'diagnostics_log_clear_failed',
        error,
        stack,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Some diagnostic files remain.')),
        );
      }
    } finally {
      await _load();
    }
  }

  void _dimensionalSync() {
    // A gag feature: we log a "multiverse fix" event.
    unawaited(
      AppLog.instance.info('dimensional_sync', <String, Object?>{
        'message':
            "Your multiversal twin already debugged this. You're welcome.",
      }),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Dimensional Sync: multiverse patch retrieved. '
          "It's mostly vibes, but it's logged.",
        ),
      ),
    );
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Refresh diagnostics',
            onPressed: () => unawaited(_load()),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Export application log',
            onPressed: _exportAppLog,
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(onPressed: _clear, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.auto_fix_high),
                    title: const Text('Dimensional Sync Fix'),
                    subtitle: const Text(
                      'When in doubt, blame the multiverse and log everything.',
                    ),
                    onTap: _dimensionalSync,
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: Listenable.merge([
                    SafeBoot.instance.safeMode,
                    SafeBoot.instance.restartRequired,
                  ]),
                  builder: (context, _) {
                    final safeMode = SafeBoot.instance.safeMode.value;
                    final restartRequired =
                        SafeBoot.instance.restartRequired.value;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          safeMode
                              ? Icons.health_and_safety
                              : Icons.verified_outlined,
                          color: safeMode ? Colors.orange : Colors.green,
                        ),
                        title: Text(
                          restartRequired
                              ? 'Restart required'
                              : safeMode
                                  ? 'Safe Mode active'
                                  : 'Normal startup mode',
                        ),
                        subtitle: Text(
                          restartRequired
                              ? 'Safe Mode remains active in this process. '
                                  'Restart Neura to return to normal startup mode.'
                              : safeMode
                                  ? 'Voice, notifications, and cloud startup '
                                      'are temporarily suppressed.'
                                  : 'Consecutive failed boots: '
                                      '${SafeBoot.instance.consecutiveFailures}',
                        ),
                        trailing: restartRequired
                            ? const Chip(label: Text('Next launch'))
                            : TextButton(
                                onPressed: _toggleSafeMode,
                                child: Text(safeMode ? 'Clear' : 'Enable'),
                              ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: ModuleHealthMonitor.instance,
                  builder: (context, _) {
                    final modules = ModuleHealthMonitor.instance.snapshot;
                    return ExpansionTile(
                      initiallyExpanded: true,
                      title: const Text('Module Health Monitor'),
                      subtitle: Text(
                        '${modules.length} startup modules reported',
                      ),
                      children: modules.map((module) {
                        final healthy =
                            module.status == NeuraModuleStatus.healthy;
                        final skipped =
                            module.status == NeuraModuleStatus.skipped;
                        return ListTile(
                          leading: Icon(
                            healthy
                                ? Icons.check_circle
                                : skipped
                                    ? Icons.pause_circle_outline
                                    : Icons.warning_amber,
                            color: healthy
                                ? Colors.green
                                : skipped
                                    ? Colors.blueGrey
                                    : Colors.orange,
                          ),
                          title: Text(module.name),
                          subtitle: Text([
                            module.status.name,
                            if (module.duration != null)
                              '${module.duration!.inMilliseconds} ms',
                            if (module.detail != null) module.detail!,
                            if (module.remedy != null)
                              'Remedy: ${module.remedy}',
                          ].join(' · ')),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  initiallyExpanded:
                      _crashes.isNotEmpty || _bootstrapErrors.isNotEmpty,
                  title: const Text('Crash and bootstrap vault'),
                  subtitle: Text(
                    _crashes.isEmpty && _bootstrapErrors.isEmpty
                        ? 'No native or early-startup failures recorded'
                        : '${_crashes.length + _bootstrapErrors.length} '
                            'privacy-filtered records',
                  ),
                  trailing: IconButton(
                    tooltip: 'Export crash diagnostics',
                    onPressed: _crashes.isEmpty && _bootstrapErrors.isEmpty
                        ? null
                        : _exportCrashLogs,
                    icon: const Icon(Icons.download_outlined),
                  ),
                  children: _crashes.isEmpty && _bootstrapErrors.isEmpty
                      ? const <Widget>[
                          ListTile(
                            leading: Icon(Icons.check_circle_outline),
                            title: Text('No crash records'),
                          ),
                        ]
                      : <Widget>[
                          if (_bootstrapErrors.isNotEmpty)
                            const ListTile(
                              dense: true,
                              title: Text('Early Dart and bootstrap errors'),
                            ),
                          ..._bootstrapErrors.reversed.map((record) {
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.shield_outlined),
                              title: Text(
                                record['source']?.toString() ??
                                    'bootstrap_error',
                              ),
                              subtitle: Text(
                                const JsonEncoder.withIndent('  ')
                                    .convert(record),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            );
                          }),
                          if (_crashes.isNotEmpty)
                            const ListTile(
                              dense: true,
                              title: Text('Runner and crash errors'),
                            ),
                          ..._crashes.reversed.map((line) {
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.bug_report_outlined),
                              title: Text(_prettyCrashTitle(line)),
                              subtitle: Text(
                                _prettyCrashDetails(line),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            );
                          }),
                        ],
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  title: const Text('Timeline Vault'),
                  subtitle: Text(
                    '${_timeline.length} recent append-only events',
                  ),
                  trailing: IconButton(
                    tooltip: 'Export Timeline Vault',
                    onPressed: _exportTimeline,
                    icon: const Icon(Icons.download_outlined),
                  ),
                  children: _timeline.reversed.map((event) {
                    final data = event['data'];
                    final receiptId =
                        data is Map ? data['receipt_id']?.toString() : null;
                    return ListTile(
                      dense: true,
                      title: Text(event['kind']?.toString() ?? 'unknown'),
                      subtitle: Text(
                        '${event['ts'] ?? ''}\n'
                        '${jsonEncode(event['data'] ?? const {})}',
                      ),
                      trailing: receiptId == null || receiptId.isEmpty
                          ? null
                          : const Tooltip(
                              message: 'View decision receipt',
                              child: Icon(Icons.arrow_forward_ios, size: 14),
                            ),
                      onTap: receiptId == null || receiptId.isEmpty
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      NeuraIntelligenceCenterScreen(
                                    initialReceiptId: receiptId,
                                  ),
                                ),
                              ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Text(
                  'Recent logs',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ..._lines.reversed.map((l) {
                  final pretty = _prettyLine(l);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        pretty,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }

  String _prettyLine(String line) {
    try {
      final obj = jsonDecode(line);
      final ts = obj['ts'] ?? '';
      final lvl = obj['level'] ?? '';
      final ev = obj['event'] ?? '';
      final data = const JsonEncoder.withIndent('  ').convert(
        obj['data'] ?? const <String, Object?>{},
      );
      return '$ts  [$lvl]  $ev\n$data';
    } catch (_) {
      return '{"type":"corrupt_record"}';
    }
  }

  String _prettyCrashTitle(String line) {
    try {
      final obj = jsonDecode(line) as Map<String, dynamic>;
      return (obj['event'] ?? obj['type'] ?? 'crash_record').toString();
    } catch (_) {
      return 'corrupt_record';
    }
  }

  String _prettyCrashDetails(String line) {
    try {
      final obj = jsonDecode(line);
      return const JsonEncoder.withIndent('  ').convert(obj);
    } catch (_) {
      return '{"type":"corrupt_record"}';
    }
  }
}
