import 'package:flutter/material.dart';

import 'mood_models.dart';
import 'mood_store.dart';

class MoodCheckInScreen extends StatefulWidget {
  const MoodCheckInScreen({super.key});

  @override
  State<MoodCheckInScreen> createState() => _MoodCheckInScreenState();
}

class _MoodCheckInScreenState extends State<MoodCheckInScreen> {
  int _mood = 5;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String get _emoji {
    if (_mood <= 1) return '😖';
    if (_mood <= 3) return '😕';
    if (_mood <= 5) return '😐';
    if (_mood <= 7) return '🙂';
    if (_mood <= 9) return '😄';
    return '🤩';
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
    setState(() => _saving = true);
    await MoodStore.instance.add(
      MoodEntry(
          timestamp: DateTime.now(), mood0to10: _mood, note: _note.text.trim()),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mood Check‑In')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Text(
              '$_emoji  $_label',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 10),
          Text('How are you doing right now?',
              style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _mood.toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            label: _mood.toString(),
            onChanged:
                _saving ? null : (v) => setState(() => _mood = v.round()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            enabled: !_saving,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Quick note (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
            label: Text(_saving ? 'Saving…' : 'Save check‑in'),
          ),
        ],
      ),
    );
  }
}
