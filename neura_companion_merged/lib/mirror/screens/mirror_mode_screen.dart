import 'package:flutter/material.dart';

import '../../mood/services/mood_state_service.dart';

class MirrorModeScreen extends StatefulWidget {
  const MirrorModeScreen({super.key});

  @override
  State<MirrorModeScreen> createState() => _MirrorModeScreenState();
}

class _MirrorModeScreenState extends State<MirrorModeScreen> {
  final _moodState = MoodStateService.instance;
  String _currentMood = 'neutral';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _moodState.load();
    if (!mounted) return;
    setState(() {
      _currentMood = _moodState.currentMood;
      _loading = false;
    });
  }

  Future<void> _setMood(String mood) async {
    await _moodState.setMood(mood);
    if (!mounted) return;
    setState(() {
      _currentMood = mood;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Mood set to "$mood". Neura will adjust tone and difficulty.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mirror Mode'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mirror Mode (stub)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This is a safe starter version of Mirror Mode.\n\nLater you can plug camera + emotion detection here.\n\nFor now, tap the mood that best matches how you feel.\n\nNeura will use this to change colors, tone, and difficulty.',
                  ),
                  const SizedBox(height: 16),
                  Text('Current mood: $_currentMood'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _moodChip('sad'),
                      _moodChip('anxious'),
                      _moodChip('angry'),
                      _moodChip('tired'),
                      _moodChip('calm'),
                      _moodChip('happy'),
                      _moodChip('excited'),
                      _moodChip('neutral'),
                    ],
                  ),
                  const Spacer(),
                  const Text(
                    "Note: Do not rely on Mirror Mode for any diagnosis. "
                    "It's just here to help Neura respond more sensitively.",
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _moodChip(String mood) {
    final selected = mood == _currentMood;
    return ChoiceChip(
      selected: selected,
      label: Text(mood),
      onSelected: (_) => _setMood(mood),
    );
  }
}
