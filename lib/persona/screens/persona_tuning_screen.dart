import '../../teaching/teach_neura_screen.dart';
import 'package:flutter/material.dart';
import '../../profiles/local_profile_service.dart';
import '../services/neura_persona_service.dart';
import '../models/persona_profile.dart';
import '../models/neura_persona_preset.dart';

class PersonaTuningScreen extends StatefulWidget {
  const PersonaTuningScreen({super.key});

  @override
  State<PersonaTuningScreen> createState() => _PersonaTuningScreenState();
}

class _PersonaTuningScreenState extends State<PersonaTuningScreen> {
  final _service = NeuraPersonaService.instance;

  late PersonaProfile _profile;
  String? _profileId;
  int? _profileEpoch;
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
      _profileId = LocalProfileService.instance.active?.id;
      _profileEpoch = LocalProfileService.instance.epoch;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    final saved = await _service.update(_profile,
        expectedProfileId: _profileId, expectedProfileEpoch: _profileEpoch);
    if (!mounted) return;
    setState(() {
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved
            ? "Neura's persona updated."
            : 'Could not save your changes. Please try again.'),
      ),
    );
  }

  Future<void> _showProfilesInfo() async {
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Separate profile setup is paused'),
                content: const SingleChildScrollView(
                    child: Text(
                        'The profile workspace keeps saved styles separate, but has no safe return to your full Neura app. '
                        'Journals, memories, planning, room navigation and voice become unavailable there. '
                        'Removing every profile or restarting still leaves that workspace active. '
                        'New setup is paused to keep your current app and saved data accessible. '
                        'You can continue personalizing Neura with the style controls here.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Keep using my Neura'))
                ]));
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
        title: const Text('Your Neura'),
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
            const Text(
              'Choose a starting style, then make it your own. Saved choices '
              'shape her replies and in-app body language on this device. '
              'You can change them anytime.',
            ),
            const SizedBox(height: 12),
            if (!LocalProfileService.instance.enabled)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(LocalProfileService.setupPausedMessage),
                            TextButton(
                                onPressed: _saving ? null : _showProfilesInfo,
                                child:
                                    const Text('About separate local profiles'))
                          ]))),
            if (!LocalProfileService.instance.enabled)
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: const Text('Teach Neura'),
                subtitle:
                    const Text('Choose answer detail and starter plan size.'),
                onTap: _saving
                    ? null
                    : () async {
                        await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => const NeuraTeachScreen()));
                      },
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in NeuraPersonaPreset.values)
                  ChoiceChip(
                    label: Text(preset.label),
                    tooltip: preset.description,
                    selected: preset.matches(_profile),
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _profile = preset.profile),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Style preview',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(personaStylePreview(_profile)),
                    const SizedBox(height: 8),
                    const Text(
                      'Sample wording. Your changes apply after saving. '
                      'Memory and voice permissions stay under your control.',
                    ),
                  ],
                ),
              ),
            ),
            _buildSlider(
              label: 'Warmth',
              description: 'Cool and factual vs warm and emotionally present.',
              value: _profile.warmth,
              onChanged: (v) => setState(
                () => _profile = _profile.copyWith(warmth: v),
              ),
            ),
            _buildSlider(
              label: 'Directness',
              description: 'Gentle hints vs straight-to-the-point truth.',
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
              description: 'Calm words and movement vs lively expression.',
              value: _profile.energy,
              onChanged: (v) => setState(
                () => _profile = _profile.copyWith(energy: v),
              ),
            ),
            _buildSlider(
              label: 'Depth',
              description: 'Quick tips vs deep reflective conversations.',
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
            TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() => _profile = PersonaProfile.neutral()),
              child: const Text('Reset draft to balanced'),
            ),
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
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Slider(
              value: value.clamp(0.0, 1.0),
              onChanged: _saving ? null : onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
