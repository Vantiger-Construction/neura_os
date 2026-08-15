import 'dart:convert';

import 'package:flutter/material.dart';

import '../../reliability/module_health_monitor.dart';
import '../../reliability/safe_boot.dart';
import '../../reliability/timeline_vault.dart';
import '../core/app_log.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<String> _lines = const [];
  List<Map<String, dynamic>> _timeline = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      AppLog.instance.tail(maxLines: 250),
      TimelineVault.instance.tail(maxLines: 50),
    ]);
    if (!mounted) return;
    setState(() {
      _lines = results[0] as List<String>;
      _timeline = results[1] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  Future<void> _exportTimeline() async {
    final path = await TimelineVault.instance.exportCopy();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Timeline exported to $path')),
    );
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
    await AppLog.instance.clear();
    await _load();
  }

  void _dimensionalSync() {
    // A gag feature: we log a "multiverse fix" event.
    AppLog.instance.info('dimensional_sync', {
      'message': "Your multiversal twin already debugged this. You're welcome.",
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Dimensional Sync: multiverse patch retrieved. (It's mostly vibes, but it's logged.)")),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
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
                    subtitle: const Text('When in doubt, blame the multiverse and log everything.'),
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
                      subtitle: Text('${modules.length} startup modules reported'),
                      children: modules.map((module) {
                        final healthy = module.status == NeuraModuleStatus.healthy;
                        final skipped = module.status == NeuraModuleStatus.skipped;
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
                            if (module.remedy != null) 'Remedy: ${module.remedy}',
                          ].join(' · ')),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  title: const Text('Timeline Vault'),
                  subtitle: Text('${_timeline.length} recent append-only events'),
                  trailing: IconButton(
                    tooltip: 'Export Timeline Vault',
                    onPressed: _exportTimeline,
                    icon: const Icon(Icons.download_outlined),
                  ),
                  children: _timeline.reversed.map((event) {
                    return ListTile(
                      dense: true,
                      title: Text(event['kind']?.toString() ?? 'unknown'),
                      subtitle: Text(
                        '${event['ts'] ?? ''}\n${jsonEncode(event['data'] ?? const {})}',
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Text('Recent logs', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ..._lines.reversed.map((l) {
                  final pretty = _prettyLine(l);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(pretty, style: const TextStyle(fontFamily: 'monospace')),
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
      return '$ts  [$lvl]  $ev\n${const JsonEncoder.withIndent('  ').convert(obj['data'] ?? {})}';
    } catch (_) {
      return line;
    }
  }
}
