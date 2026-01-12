import 'package:flutter/material.dart';
import '../services/neura_persona_service.dart';
import '../models/persona_profile.dart';

class PersonaTuningScreen extends StatefulWidget {
  const PersonaTuningScreen({super.key});

  @override
  State<PersonaTuningScreen> createState() => _PersonaTuningScreenState();
}

class _PersonaTuningScreenState extends State<PersonaTuningScreen> {
  final _service = NeuraPersonaService.instance;

  late PersonaProfile _profile;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _service.load();
    if (!mounted) return;
    setState(() {
      _profile = _service.current;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    await _service.update(_profile);
    if (!mounted) return;
    setState(() {
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Neura's persona updated.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final previewText = _service.describePersona(_profile);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neura Persona Tuning'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'How do you want Neura to show up for you?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildSlider(
              label: 'Warmth',
              description:
                  'Cool and factual vs warm and emotionally present.',
              value: _profile.warmth,
              onChanged: (v) => setState(
                () => _profile = _profile.copyWith(warmth: v),
              ),
            ),
            _buildSlider(
              label: 'Directness',
              description:
                  'Gentle hints vs straight-to-the-point truth.',
              value: _profile.directness,
              onChanged: (v) => setState(
                () => _profile = _profile.copyWith(directness: v),
              ),
            ),
            _buildSlider(
              label: 'Humor',
              description: 'Serious mode vs lots of playful jokes.',
              value: _profile.humor,
              onChanged: (v) => setState(
                () => _profile = _profile.copyWith(humor: v),
              ),
            ),
            _buildSlider(
              label: 'Energy',
              description: 'Calm and slow vs hyped and energetic.',
              value: _profile.energy,
              onChanged: (v) => setState(
                () => _profile = _profile.copyWith(energy: v),
              ),
            ),
            _buildSlider(
              label: 'Depth',
              description:
                  'Quick tips vs deep reflective conversations.',
              value: _profile.depth,
              onChanged: (v) => setState(
                () => _profile = _profile.copyWith(depth: v),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: Colors.blueGrey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        previewText,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save persona'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required String description,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            Slider(
              value: value.clamp(0.0, 1.0),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
