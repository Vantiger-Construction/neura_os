import 'package:flutter/material.dart';

import '../../reliability/safe_boot.dart';
import 'mood_models.dart';
import 'mood_store.dart';

class MoodHistoryScreen extends StatefulWidget {
  const MoodHistoryScreen({super.key, this.load, this.now});
  final Future<List<MoodEntry>> Function()? load;
  final DateTime Function()? now;

  @override
  State<MoodHistoryScreen> createState() => _MoodHistoryScreenState();
}

class _MoodHistoryScreenState extends State<MoodHistoryScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _failed = false;
  bool _hidden = false;
  bool _foreground = true;
  bool _visible = true;
  int _request = 0;
  List<MoodEntry> _items = const [];
  MoodSummary? _summary;
  bool get _ready =>
      _foreground && _visible && !SafeBoot.instance.restartRequired.value;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafety);
    SafeBoot.instance.restartRequired.addListener(_onSafety);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (_ready) {
      _load();
    } else {
      _hide();
    }
  }

  void _hide() {
    _request++;
    _items = const [];
    _summary = null;
    _loading = false;
    _failed = false;
    _hidden = true;
  }

  void _onSafety() {
    if (mounted) setState(_hide);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground) _hide();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = ModalRoute.isCurrentOf(context) ?? true;
    if (!_visible) _hide();
  }

  @override
  void dispose() {
    _request++;
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafety);
    SafeBoot.instance.restartRequired.removeListener(_onSafety);
    super.dispose();
  }

  Future<void> _load() async {
    if (!_ready) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
      _hidden = false;
    });
    try {
      final items = await (widget.load ?? MoodStore.instance.getAll)();
      if (!mounted || request != _request || !_ready) return;
      final ordered = [...items]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      setState(() {
        _items = ordered.take(120).toList();
        _summary = MoodSummary(items, (widget.now ?? DateTime.now)());
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request || !_ready) return;
      setState(() {
        _items = [];
        _summary = null;
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mood History'), actions: [
          IconButton(
              tooltip: 'Hide history',
              onPressed: _hidden ? null : () => setState(_hide),
              icon: const Icon(Icons.visibility_off_outlined)),
          IconButton(
              tooltip: 'Refresh history',
              onPressed: _loading || _hidden || !_ready ? null : _load,
              icon: const Icon(Icons.refresh))
        ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                if (_hidden) ...[
                  Text('History is hidden',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                      'Open your saved check-ins when you are ready. Your saved entries have not been changed.'),
                  if (SafeBoot.instance.restartRequired.value)
                    const Text('Restart Neura before opening saved history.'),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: _ready ? _load : null,
                      child: const Text('Show saved history')),
                ],
                if (_failed)
                  const Text(
                      'History could not be opened. Your saved entries have not been changed. Try refreshing.'),
                if (_summary case final summary?)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Past seven days',
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                Text('${summary.count} mood check-ins'),
                                if (summary.moodAverage != null)
                                  Text(
                                      'Average recorded mood: ${summary.moodAverage!.toStringAsFixed(1)}/10'),
                                Text(summary.energyAverage == null
                                    ? 'Energy: not recorded'
                                    : 'Average recorded energy: ${summary.energyAverage!.toStringAsFixed(1)}/10 (${summary.energyCount} entries)'),
                                Text(summary.sleepAverage == null
                                    ? 'Sleep: not recorded'
                                    : 'Average recorded sleep: ${summary.sleepAverage!.toStringAsFixed(1)} hours (${summary.sleepCount} entries)'),
                                const SizedBox(height: 8),
                                const Text(
                                    'These are averages of your check-ins, not daily measurements or a diagnosis. '
                                    'Missing information is left out. These numbers do not establish causes.'),
                              ]))),
                if (!_hidden && !_failed && _items.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No check-ins yet.')),
                for (final entry in _items)
                  Card(
                      child: ListTile(
                    title: Text(
                        '${_when(entry.timestamp)} · Mood ${entry.mood0to10}/10'),
                    subtitle: Text([
                      if (entry.energy0to10 != null)
                        'Energy ${entry.energy0to10}/10',
                      if (entry.sleepHours != null)
                        'Sleep ${entry.sleepHours!.toStringAsFixed(1)} hours',
                      if (entry.note.isNotEmpty) entry.note,
                    ].join('\n')),
                  )),
              ]),
      );

  String _when(DateTime timestamp) {
    final local = timestamp.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
