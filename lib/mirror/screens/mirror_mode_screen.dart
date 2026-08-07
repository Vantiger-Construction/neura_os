import 'package:flutter/material.dart';

import '../../core/memory/memory_graph_service.dart';
import '../../mood/services/mood_state_service.dart';

/// A short guided check-in: name the feeling, say a line about what's behind
/// it, then a quiet close-out. No camera/emotion detection (that's future
/// work) -- this is a deliberately simple, local, non-diagnostic ritual that
/// actually contributes to Neura's memory of the user, unlike the old stub
/// which only wrote to MoodStateService.
class MirrorModeScreen extends StatefulWidget {
  const MirrorModeScreen({super.key});

  @override
  State<MirrorModeScreen> createState() => _MirrorModeScreenState();
}

enum _Step { mood, reflect, done }

class _MirrorModeScreenState extends State<MirrorModeScreen> {
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

  final _reflectionController = TextEditingController();
  String _mood = 'neutral';
  _Step _step = _Step.mood;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await MoodStateService.instance.load();
    if (!mounted) return;
    setState(() {
      _mood = MoodStateService.instance.currentMood;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _reflectionController.dispose();
    super.dispose();
  }

  void _pickMood(String mood) {
    setState(() => _mood = mood);
  }

  void _goToReflect() {
    setState(() => _step = _Step.reflect);
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);

    await MoodStateService.instance.setMood(_mood);

    final reflection = _reflectionController.text.trim();
    try {
      await MemoryGraphService.I.logUserAction(
        kind: 'MIRROR_CHECKIN',
        payload: {
          'mood': _mood,
          if (reflection.isNotEmpty) 'reflection': reflection,
        },
      );
    } catch (_) {
      // A memory-write failure shouldn't block finishing the check-in.
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _step = _Step.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mirror Mode')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: switch (_step) {
                _Step.mood => _moodStep(),
                _Step.reflect => _reflectStep(),
                _Step.done => _doneStep(),
              },
            ),
    );
  }

  Widget _moodStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How are you feeling right now?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _moods.map((m) {
            return ChoiceChip(
              selected: m == _mood,
              label: Text(m),
              onSelected: (_) => _pickMood(m),
            );
          }).toList(),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(onPressed: _goToReflect, child: const Text('Next')),
        ),
        const SizedBox(height: 8),
        const Text(
          "Note: Mirror Mode isn't a diagnosis. It just helps Neura respond more sensitively.",
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _reflectStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "You're feeling $_mood. Want to say a bit about what's behind that?",
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Totally optional -- leave it blank if you\'d rather not.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reflectionController,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: "What's on your mind...",
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _finish,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Done'),
          ),
        ),
      ],
    );
  }

  Widget _doneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.self_improvement, size: 48),
        const SizedBox(height: 16),
        const Text(
          "Thanks for checking in.",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          "Neura will keep this in mind -- colors, tone, and pacing will adjust to match.",
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Rooms'),
          ),
        ),
      ],
    );
  }
}
