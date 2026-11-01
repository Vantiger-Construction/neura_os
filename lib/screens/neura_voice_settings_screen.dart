import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/neura_tts_service.dart';
import '../services/neura_local_speech_input.dart';
import '../services/neura_startup_voice_prefs.dart';
import '../reliability/safe_boot.dart';
import '../modules/chat/neura_chat_screen.dart';

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
  NeuraReplySpeechMode _replySpeechMode = NeuraReplySpeechMode.off;
  bool _savingStartup = false;

  Future<void> _setStartupVoice(bool value) async {
    setState(() => _savingStartup = true);
    try {
      if (value) {
        if (!await NeuraLocalSpeechInput.instance.isAvailable()) {
          throw StateError('Install an on-device speech language pack first.');
        }
        if (defaultTargetPlatform == TargetPlatform.android &&
            !(await Permission.microphone.request()).isGranted) {
          throw StateError('Allow microphone access to use startup voice.');
        }
        if (!mounted ||
            SafeBoot.instance.safeMode.value ||
            SafeBoot.instance.restartRequired.value) {
          return;
        }
        await NeuraTtsService.instance.prepareLocalStartupVoice();
      }
      await NeuraStartupVoicePrefs.instance.setEnabled(value);
      if (value &&
          NeuraTtsService.instance.replySpeechMode ==
              NeuraReplySpeechMode.off) {
        await NeuraTtsService.instance
            .setReplySpeechMode(NeuraReplySpeechMode.afterComplete);
      }
      if (mounted) {
        setState(
            () => _replySpeechMode = NeuraTtsService.instance.replySpeechMode);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error is StateError
              ? error.message.toString()
              : 'Startup voice could not be saved. You can still type.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _savingStartup = false);
    }
  }

  Widget _startupVoiceControls() => ValueListenableBuilder<bool>(
        valueListenable: NeuraStartupVoicePrefs.instance.enabled,
        builder: (context, enabled, _) => Column(children: [
          SwitchListTile(
            key: const Key('startup-voice-switch'),
            title: const Text('Voice on startup'),
            subtitle: const Text(
                'Open voice chat, greet you, then listen on this device. '
                'Stops when Neura leaves the foreground. Cloud replies still need approval.'),
            value: enabled,
            onChanged: _savingStartup ||
                    kIsWeb ||
                    SafeBoot.instance.safeMode.value ||
                    SafeBoot.instance.restartRequired.value ||
                    (defaultTargetPlatform != TargetPlatform.windows &&
                        defaultTargetPlatform != TargetPlatform.android)
                ? null
                : _setStartupVoice,
          ),
          if (enabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _savingStartup ||
                        SafeBoot.instance.safeMode.value ||
                        SafeBoot.instance.restartRequired.value
                    ? null
                    : () {
                        Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) =>
                              const NeuraChatScreen(startWithVoice: true),
                        ));
                      },
                icon: const Icon(Icons.mic),
                label: const Text('Start voice now'),
              ),
            ),
          const Divider(),
        ]),
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    final service = NeuraTtsService.instance;
    unawaited(service
        .stop()
        .then((_) => service.restoreSelectedVoice())
        .catchError((Object _) {}));
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
      _replySpeechMode = service.replySpeechMode;
      _loading = false;
    });
  }

  Future<void> _select(String? name) async {
    if (name == null) return;
    final voice = _voices.firstWhere((option) => option.name == name);
    setState(() => _selected = name);
    await NeuraTtsService.instance.setVoice(voice);
  }

  void _setReplySpeechMode(NeuraReplySpeechMode? mode) {
    if (mode == null) return;
    setState(() => _replySpeechMode = mode);
    unawaited(NeuraTtsService.instance.setReplySpeechMode(mode));
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
          : ListView(
              children: [
                _startupVoiceControls(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Automatic reply speech',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      RadioGroup<NeuraReplySpeechMode>(
                        groupValue: _replySpeechMode,
                        onChanged: _setReplySpeechMode,
                        child: Column(
                          children: [
                            for (final mode in NeuraReplySpeechMode.values)
                              RadioListTile<NeuraReplySpeechMode>(
                                value: mode,
                                title: Text(mode.label),
                                subtitle: Text(mode.description),
                              ),
                          ],
                        ),
                      ),
                    ],
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
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No voices found on this system. Windows Speech may not be installed.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  RadioGroup<String>(
                    groupValue: _selected,
                    onChanged: _select,
                    child: Column(
                      children: [
                        for (final voice in _voices)
                          RadioListTile<String>(
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
                          )
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
