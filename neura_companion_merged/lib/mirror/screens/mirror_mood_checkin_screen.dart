import 'package:flutter/material.dart';

import '../../mood/services/mood_state_service.dart';

class MirrorMoodCheckinScreen extends StatefulWidget {
  const MirrorMoodCheckinScreen({super.key});

  @override
  State<MirrorMoodCheckinScreen> createState() =>
      _MirrorMoodCheckinScreenState();
}

class _MirrorMoodCheckinScreenState extends State<MirrorMoodCheckinScreen> {
  double _score = 5.0;
  String _note = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await MoodStateService.instance.load();
    final current = MoodStateService.instance.current;
    if (!mounted) return;
    setState(() {
      _score = current.score;
      _note = current.note;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await MoodStateService.instance.setScore(_score, note: _note);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mood updated. Neura will adjust accordingly.')),
    );
    Navigator.of(context).pop();
  }

  String _scoreLabel(double value) {
    if (value <= 2.5) return 'Really rough';
    if (value <= 4.0) return 'Pretty low';
    if (value <= 6.0) return 'In the middle';
    if (value <= 8.0) return 'Lifted';
    return 'Energized';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mirror Check-in'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How are you feeling right now?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Slider(
              min: 0,
              max: 10,
              divisions: 20,
              label: _score.toStringAsFixed(1),
              value: _score,
              onChanged: (v) {
                setState(() {
                  _score = v;
                });
              },
            ),
            Text(
              '${_score.toStringAsFixed(1)}/10 · ${_scoreLabel(_score)}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'Anything you want Neura to know about this moment?',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Optional note (e.g., "long day at work", "big win today")',
              ),
              maxLines: 3,
              onChanged: (v) => _note = v,
              controller: TextEditingController(text: _note),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Neura will quietly use this check-in to adjust colors, tone, and difficulty.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
