import 'package:flutter/material.dart';

import '../services/neura_tts_service.dart';

const _sampleText = "Hi, I'm Neura. This is what I sound like.";

class NeuraVoiceSettingsScreen extends StatefulWidget {
  const NeuraVoiceSettingsScreen({super.key});

  @override
  State<NeuraVoiceSettingsScreen> createState() =>
      _NeuraVoiceSettingsScreenState();
}

class _NeuraVoiceSettingsScreenState extends State<NeuraVoiceSettingsScreen> {
  List<NeuraVoiceOption> _voices = const [];
  bool _loading = true;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Undo any un-selected preview so real chat replies use the saved voice.
    NeuraTtsService.instance.restoreSelectedVoice();
    super.dispose();
  }

  Future<void> _load() async {
    final voices = await NeuraTtsService.instance.availableVoices();
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _selected = NeuraTtsService.instance.selectedVoiceName;
      _loading = false;
    });
  }

  Future<void> _select(String? name) async {
    if (name == null) return;
    final voice = _voices.firstWhere((v) => v.name == name);
    setState(() => _selected = name);
    await NeuraTtsService.instance.setVoice(voice);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Neura's Voice")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _voices.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No voices found on this system. Windows Speech may not be installed.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        'Tap a voice to select it, or tap play to hear a sample first.',
                      ),
                    ),
                    Expanded(
                      child: RadioGroup<String>(
                        groupValue: _selected,
                        onChanged: _select,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _voices.length,
                          itemBuilder: (context, i) {
                            final v = _voices[i];
                            return RadioListTile<String>(
                              value: v.name,
                              title: Text(v.name),
                              subtitle: Text('${v.locale} · ${v.gender}'),
                              secondary: IconButton(
                                icon: const Icon(Icons.play_arrow),
                                tooltip: 'Play a sample',
                                onPressed: () => NeuraTtsService.instance
                                    .previewVoice(v, _sampleText),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
