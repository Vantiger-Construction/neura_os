import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../services/neura_tts_service.dart';
import '../services/neura_startup_voice_prefs.dart';
import '../services/neura_startup_voice_setup.dart';
import '../reliability/safe_boot.dart';
import '../modules/chat/neura_chat_screen.dart';
import '../widgets/neura_safe_mode_switch.dart';

const _sampleText = "Hi, I'm Neura. This is what I sound like.";

class NeuraVoiceSettingsScreen extends StatefulWidget {
  const NeuraVoiceSettingsScreen({super.key, this.service});

  /// Optional isolated service for synthetic settings tests.
  final NeuraTtsService? service;

  @override
  State<NeuraVoiceSettingsScreen> createState() =>
      _NeuraVoiceSettingsScreenState();
}

class _NeuraVoiceSettingsScreenState extends State<NeuraVoiceSettingsScreen>
    with WidgetsBindingObserver {
  NeuraTtsService get _service => widget.service ?? NeuraTtsService.instance;
  List<NeuraVoiceOption> _voices = const [];
  bool _loading = true;
  String? _selected;
  String _accent = 'all';
  bool _savingVoice = false;
  bool _playingSample = false;
  bool _stoppingSample = false;
  bool _needsVoiceRestore = false;
  bool _foreground = true;
  int _voiceOperation = 0;
  double _rate = 0.5;
  double _pitch = 1.05;
  double _volume = 1.0;
  NeuraReplySpeechMode _replySpeechMode = NeuraReplySpeechMode.off;
  bool _savingStartup = false;
  bool _replySoundOnStartup = true;

  Future<void> _setReplySoundOnStartup(bool value) async {
    try {
      await _service.setReplySoundOnStartup(value);
      if (mounted) setState(() => _replySoundOnStartup = value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Startup sound preference could not be saved.'),
          ),
        );
      }
    }
  }

  Future<void> _setStartupVoice(bool value) async {
    setState(() => _savingStartup = true);
    try {
      await NeuraStartupVoiceSetup.setEnabled(
        value,
        stillWanted: () => mounted,
      );
      if (mounted) {
        setState(() => _replySpeechMode = _service.replySpeechMode);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message.toString()
                  : 'Startup voice could not be saved. You can still type.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingStartup = false);
    }
  }

  Widget _startupVoiceControls() => AnimatedBuilder(
        animation: Listenable.merge([
          NeuraStartupVoicePrefs.instance.enabled,
          SafeBoot.instance.safeMode,
          SafeBoot.instance.restartRequired,
        ]),
        builder: (context, _) {
          final enabled = NeuraStartupVoicePrefs.instance.enabled.value;
          return Column(
            children: [
              SwitchListTile(
                key: const Key('startup-voice-switch'),
                title: const Text('Voice on startup'),
                subtitle: const Text(
                  'Open voice chat, greet you, then listen on this device. '
                  'Stops when Neura leaves the foreground. Cloud replies still need approval.',
                ),
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
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const NeuraChatScreen(startWithVoice: true),
                              ),
                            );
                          },
                    icon: const Icon(Icons.mic),
                    label: const Text('Start voice now'),
                  ),
                ),
              const Divider(),
            ],
          );
        },
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    SafeBoot.instance.safeMode.addListener(_safetyChanged);
    SafeBoot.instance.restartRequired.addListener(_safetyChanged);
    _load();
  }

  @override
  void dispose() {
    _voiceOperation++;
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_safetyChanged);
    SafeBoot.instance.restartRequired.removeListener(_safetyChanged);
    final service = _service;
    unawaited(
      service
          .stop()
          .then((_) => service.restoreSelectedVoice())
          .catchError((Object _) {}),
    );
    super.dispose();
  }

  bool get _canPlay =>
      _foreground &&
      _service.playbackAllowed &&
      !SafeBoot.instance.restartRequired.value;

  bool get _voiceBusy => _savingVoice || _playingSample || _stoppingSample;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground || _needsVoiceRestore) unawaited(_stopSample());
    if (mounted) setState(() {});
  }

  void _safetyChanged() {
    if (!_canPlay) unawaited(_stopSample());
    if (mounted) setState(() {});
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String? _currentVoiceId() {
    for (final voice in _voices) {
      if (voice.name == _service.selectedVoiceName &&
          voice.locale == _service.selectedVoiceLocale) {
        return voice.id;
      }
    }
    return null;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final voices = await _service.availableVoices();
      if (!mounted) return;
      setState(() {
        _voices = voices;
        _selected = _currentVoiceId();
        if (!_voices.any((voice) => voice.accentKey == _accent)) {
          _accent = 'all';
        }
        _rate = _service.speechRate;
        _pitch = _service.pitch;
        _volume = _service.volume;
        _replySpeechMode = _service.replySpeechMode;
        _replySoundOnStartup = _service.replySoundOnStartup;
      });
    } catch (_) {
      _notice('Voices could not be loaded. You can try Refresh voices.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(String? id) async {
    if (id == null || id == _selected || _voiceBusy || !_canPlay) return;
    final voice = _voices.firstWhere((option) => option.id == id);
    setState(() => _savingVoice = true);
    try {
      await _service.stop();
      if (!mounted || !_canPlay) return;
      await _service.setVoice(voice);
      if (!mounted) return;
      setState(() => _selected = _currentVoiceId());
      if (_selected != id) _notice('That voice could not be selected.');
    } catch (_) {
      _notice('That voice could not be selected.');
    } finally {
      if (mounted) setState(() => _savingVoice = false);
    }
  }

  Future<void> _setRate(double rate) async {
    setState(() => _rate = rate);
    try {
      await _service.setSpeechRate(rate);
    } catch (_) {
      _notice('Speaking speed could not be applied.');
    }
  }

  Future<void> _preview(NeuraVoiceOption voice) async {
    if (_voiceBusy || !_canPlay) return;
    final operation = ++_voiceOperation;
    _needsVoiceRestore = true;
    setState(() => _playingSample = true);
    try {
      await _service.previewVoice(voice, _sampleText);
    } catch (_) {
      if (operation == _voiceOperation) {
        _notice('The voice sample could not play.');
      }
    } finally {
      if (mounted && operation == _voiceOperation) {
        try {
          if (_canPlay) {
            await _service.restoreSelectedVoice();
            _needsVoiceRestore = false;
          }
        } catch (_) {
          _notice('The selected voice could not be restored.');
        }
        if (mounted) setState(() => _playingSample = false);
      }
    }
  }

  Future<void> _stopSample() async {
    final operation = ++_voiceOperation;
    if (mounted) setState(() => _stoppingSample = true);
    try {
      await _service.stop();
      if (mounted && operation == _voiceOperation && _canPlay) {
        await _service.restoreSelectedVoice();
        _needsVoiceRestore = false;
      }
    } catch (_) {
      _notice(
        'Speech could not be stopped. Restart Neura before trying again.',
      );
    } finally {
      if (mounted && operation == _voiceOperation) {
        setState(() {
          _playingSample = false;
          _stoppingSample = false;
        });
      }
    }
  }

  Widget _voiceChoices() {
    final accents = <String, String>{
      for (final voice in _voices) voice.accentKey: voice.accentLabel,
    };
    final visible = _voices.where(
      (voice) => _accent == 'all' || voice.accentKey == _accent,
    );
    final selected =
        _voices.where((voice) => voice.id == _selected).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Voice and accent',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Browse an accent, then choose a voice. Only installed '
                'local English voices are listed; available accents depend on this device.',
              ),
              if (selected != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Selected: ${selected.name} · ${selected.accentLabel}',
                  key: const Key('selected-voice-summary'),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('refresh-voices'),
                    onPressed: _voiceBusy || !_canPlay ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh voices'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('stop-voice-sample'),
                    onPressed: _playingSample ? _stopSample : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop sample'),
                  ),
                ],
              ),
              if (_voices.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  key: const Key('voice-accent-filter'),
                  padding: EdgeInsets.zero,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(_accent),
                    initialValue: _accent,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Accent'),
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All installed accents'),
                      ),
                      for (final entry in accents.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: _voiceBusy
                        ? null
                        : (value) {
                            if (value != null) setState(() => _accent = value);
                          },
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_voices.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No installed local English voices were found. '
              'Refresh after adding a voice in your device’s speech settings. '
              'Voice previews stay off in Safe Mode or while a restart is required.',
            ),
          )
        else
          RadioGroup<String>(
            groupValue: _selected,
            onChanged: _select,
            child: Column(
              children: [
                for (final voice in visible)
                  RadioListTile<String>(
                    key: ValueKey('voice-${voice.id}'),
                    value: voice.id,
                    enabled: !_voiceBusy && _canPlay,
                    title: Text(voice.name),
                    subtitle: Text(
                      voice.gender == 'unknown'
                          ? voice.accentLabel
                          : '${voice.accentLabel} · ${voice.gender}',
                    ),
                    secondary: IconButton(
                      icon: const Icon(Icons.play_arrow),
                      tooltip: 'Play a sample',
                      onPressed: _voiceBusy || !_canPlay
                          ? null
                          : () => _preview(voice),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  void _setReplySpeechMode(NeuraReplySpeechMode? mode) {
    if (mode == null) return;
    setState(() => _replySpeechMode = mode);
    unawaited(_service.setReplySpeechMode(mode));
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    Key? sliderKey,
    String? valueLabel,
  }) {
    return Semantics(
      label: label,
      value: valueLabel ?? value.toStringAsFixed(2),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(valueLabel ?? value.toStringAsFixed(2)),
            ],
          ),
          Slider(
            key: sliderKey,
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    return Scaffold(
      appBar: AppBar(title: const Text("Neura's Voice")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const NeuraSafeModeSwitch(),
                const Divider(),
                SwitchListTile(
                  key: const Key('reply-sound-on-startup-switch'),
                  title: const Text('Spoken replies on startup'),
                  subtitle: const Text(
                    'Turn reply speech on when Neura opens. '
                    'Restore muted voice volume to 70%.',
                  ),
                  value: _replySoundOnStartup,
                  onChanged: _setReplySoundOnStartup,
                ),
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
                        label: 'Speaking speed',
                        sliderKey: const Key('speech-rate-slider'),
                        valueLabel: (_rate - 0.5).abs() < 0.001
                            ? 'Normal'
                            : (_rate < 0.5 ? 'Slower' : 'Faster'),
                        value: _rate,
                        min: 0.25,
                        max: 0.75,
                        onChanged: (value) => setState(() => _rate = value),
                        onChangeEnd: (value) => unawaited(_setRate(value)),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final preset in const [
                            (label: 'Slower', rate: 0.35),
                            (label: 'Normal', rate: 0.5),
                            (label: 'Faster', rate: 0.65),
                          ])
                            ChoiceChip(
                              key: ValueKey(
                                'speech-speed-${preset.label.toLowerCase()}',
                              ),
                              label: Text(preset.label),
                              selected: (_rate - preset.rate).abs() < 0.001,
                              onSelected: (_) =>
                                  unawaited(_setRate(preset.rate)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Speed applies to the next sample or reply. '
                        'Actual pace varies by voice. Turn off Match my mood '
                        'below for a steady pace.',
                      ),
                      const SizedBox(height: 16),
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
                      SwitchListTile(
                        key: const Key('match-mood-switch'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Match my mood'),
                        subtitle: const Text(
                          'Speak a little slower and softer when you are '
                          'having a hard time, brighter for good news.',
                        ),
                        value: service.matchMood,
                        onChanged: (value) async {
                          await service.setMatchMood(value);
                          if (mounted) setState(() {});
                        },
                      ),
                      const Text(
                        'Settings stay on this device. Ambient sound lowers automatically while Neura speaks.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                _voiceChoices(),
              ],
            ),
    );
  }
}
