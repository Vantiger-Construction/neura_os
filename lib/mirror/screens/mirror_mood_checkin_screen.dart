import 'package:flutter/material.dart';

import '../../mood/services/mood_state_service.dart';

class MirrorMoodCheckinScreen extends StatefulWidget {
  const MirrorMoodCheckinScreen({super.key});

  @override
  State<MirrorMoodCheckinScreen> createState() =>
      _MirrorMoodCheckinScreenState();
}

class _MirrorMoodCheckinScreenState extends State<MirrorMoodCheckinScreen> {
  static const List<String> _moods = <String>[
    'sad',
    'anxious',
    'angry',
    'tired',
    'calm',
    'happy',
    'excited',
    'neutral',
  ];

  String _mood = 'neutral';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await MoodStateService.instance.load();
    final current = MoodStateService.instance.currentMood;
    if (!mounted) return;
    setState(() {
      _mood = current;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await MoodStateService.instance.setMood(_mood);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Mood updated. Neura will adjust accordingly.')),
    );
    Navigator.of(context).pop();
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _moods
                  .map(
                    (m) => ChoiceChip(
                      selected: _mood == m,
                      label: Text(m),
                      onSelected: (_) => setState(() => _mood = m),
                    ),
                  )
                  .toList(),
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
