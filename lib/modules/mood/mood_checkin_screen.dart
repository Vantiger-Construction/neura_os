import 'package:flutter/material.dart';

import '../../reliability/safe_boot.dart';
import 'mood_models.dart';
import 'mood_store.dart';

class MoodCheckInScreen extends StatefulWidget {
  const MoodCheckInScreen({super.key, this.save});
  final Future<void> Function(MoodEntry entry)? save;

  @override
  State<MoodCheckInScreen> createState() => _MoodCheckInScreenState();
}

class _MoodCheckInScreenState extends State<MoodCheckInScreen>
    with WidgetsBindingObserver {
  final _note = TextEditingController();
  int _mood = 5;
  int _energy = 5;
  double _sleep = 8;
  bool _recordEnergy = false;
  bool _recordSleep = false;
  bool _saving = false;
  String? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_clearDraft);
    SafeBoot.instance.restartRequired.addListener(_clearDraft);
  }

  void _clearDraft() {
    _epoch++;
    _note.clear();
    if (mounted) {
      setState(() {
        _mood = 5;
        _energy = 5;
        _sleep = 8;
        _recordEnergy = false;
        _recordSleep = false;
        _error = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clearDraft();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.isCurrentOf(context) == false) _clearDraft();
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_clearDraft);
    SafeBoot.instance.restartRequired.removeListener(_clearDraft);
    _note.dispose();
    super.dispose();
  }

  String get _label {
    if (_mood <= 1) return 'Rough';
    if (_mood <= 3) return 'Low';
    if (_mood <= 5) return 'Neutral';
    if (_mood <= 7) return 'Okay';
    if (_mood <= 9) return 'Good';
    return 'Excellent';
  }

  Future<void> _save() async {
    if (_saving || SafeBoot.instance.restartRequired.value) return;
    final epoch = _epoch;
    final entry = MoodEntry(
        timestamp: DateTime.now(),
        mood0to10: _mood,
        note: _note.text.trim(),
        energy0to10: _recordEnergy ? _energy : null,
        sleepHours: _recordSleep ? _sleep : null);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await (widget.save ?? MoodStore.instance.add)(entry);
      if (!mounted || epoch != _epoch) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() => _error =
          'Could not save this check-in. Your draft is still here; you can try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mood Check-In')),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text('$_label · $_mood/10',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 10),
            const Text(
                'How are you doing right now? (0 very low, 10 very good)'),
            Slider(
                value: _mood.toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                label: 'Mood $_mood out of 10',
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _mood = value.round())),
            const Text(
                'This check-in is optional. Save only what you want to keep in your encrypted local history.'),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include energy (optional)'),
                value: _recordEnergy,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _recordEnergy = value!)),
            if (_recordEnergy) ...[
              Text('Energy: $_energy/10 (0 very low, 10 very high)'),
              Slider(
                  key: const ValueKey('energy-slider'),
                  value: _energy.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: 'Energy $_energy out of 10',
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _energy = value.round())),
            ],
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include sleep (optional)'),
                value: _recordSleep,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _recordSleep = value!)),
            if (_recordSleep) ...[
              Text(
                  'Sleep in the past 24 hours: ${_sleep.toStringAsFixed(1)} hours'),
              Slider(
                  key: const ValueKey('sleep-slider'),
                  value: _sleep,
                  min: 0,
                  max: 24,
                  divisions: 48,
                  label: '${_sleep.toStringAsFixed(1)} hours of sleep',
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _sleep = value)),
            ],
            TextField(
                key: ValueKey(_epoch),
                controller: _note,
                enabled: !_saving,
                maxLines: 4,
                maxLength: 2000,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                    labelText: 'Quick note (optional)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 14),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save check-in')),
            TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Skip without saving')),
          ]),
        ))),
      );
}
