import 'dart:async';

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
  double _rate = 0.5;
  double _pitch = 1.05;
  double _volume = 1.0;
  bool _speakReplies = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    NeuraTtsService.instance.restoreSelectedVoice();
    super.dispose();
  }

  Future<void> _load() async {
    final service = NeuraTtsService.instance;
    final voices = await service.availableVoices();
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _selected = service.selectedVoiceName;
      _rate = service.speechRate;
      _pitch = service.pitch;
      _volume = service.volume;
      _speakReplies = service.speakRepliesEnabled;
      _loading = false;
    });
  }

  Future<void> _select(String? name) async {
    if (name == null) return;
    final voice = _voices.firstWhere((option) => option.name == name);
    setState(() => _selected = name);
    await NeuraTtsService.instance.setVoice(voice);
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Semantics(
      label: label,
      value: value.toStringAsFixed(2),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label)),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(value.toStringAsFixed(2), textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = NeuraTtsService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text("Neura's Voice")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SwitchListTile(
                  value: _speakReplies,
                  onChanged: (value) {
                    setState(() => _speakReplies = value);
                    unawaited(service.setSpeakRepliesEnabled(value));
                  },
                  title: const Text("Speak Neura's replies aloud"),
                  subtitle: const Text(
                    'Off by default. When on, chat replies are spoken as they '
                    'arrive; talking or typing stops playback immediately.',
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Column(
                    children: [
                      _slider(
                        label: 'Rate',
                        value: _rate,
                        min: 0.25,
                        max: 0.75,
                        onChanged: (value) => setState(() => _rate = value),
                        onChangeEnd: service.setSpeechRate,
                      ),
                      _slider(
                        label: 'Pitch',
                        value: _pitch,
                        min: 0.5,
                        max: 2.0,
                        onChanged: (value) => setState(() => _pitch = value),
                        onChangeEnd: service.setPitch,
                      ),
                      _slider(
                        label: 'Volume',
                        value: _volume,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (value) => setState(() => _volume = value),
                        onChangeEnd: service.setVolume,
                      ),
                      const Text(
                        'Settings stay on this device. Ambient sound lowers automatically while Neura speaks.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                if (_voices.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No voices found on this system. Windows Speech may not be installed.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: RadioGroup<String>(
                      groupValue: _selected,
                      onChanged: _select,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _voices.length,
                        itemBuilder: (context, index) {
                          final voice = _voices[index];
                          return RadioListTile<String>(
                            value: voice.name,
                            title: Text(voice.name),
                            subtitle: Text(
                              '${voice.locale} · ${voice.gender}',
                            ),
                            secondary: IconButton(
                              icon: const Icon(Icons.play_arrow),
                              tooltip: 'Play a sample',
                              onPressed: () => service.previewVoice(
                                voice,
                                _sampleText,
                              ),
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
