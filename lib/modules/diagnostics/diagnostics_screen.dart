import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_log.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<String> _lines = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final lines = await AppLog.instance.tail(maxLines: 250);
    setState(() {
      _lines = lines;
      _loading = false;
    });
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
