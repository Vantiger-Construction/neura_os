// Opt-in interactive Windows diagnostics; never the production entry point.
// Run only on an authorized physical Windows machine. See the acceptance doc.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_audio_focus.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';

void main() {
  if (!Platform.isWindows) {
    throw UnsupportedError('This manual acceptance harness requires Windows.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  // No application boot, preferences, credentials, models, journal, microphone
  // or mascot startup. TTS uses the real registered Windows plugin and defaults.
  runApp(const MaterialApp(home: _SpeechSmoke()));
}

class _SpeechSmoke extends StatefulWidget {
  const _SpeechSmoke();

  @override
  State<_SpeechSmoke> createState() => _SpeechSmokeState();
}

class _SpeechSmokeState extends State<_SpeechSmoke>
    with WidgetsBindingObserver {
  static const _short = 'Synthetic speech check. Alpha, beta, gamma.';
  static final _long = List.filled(
    12,
    'This is a synthetic local speech test. Stop or Safe Mode should end it.',
  ).join(' ');
  final _service = NeuraTtsService.instance;
  StreamSubscription<bool>? _focus;
  String _status = 'Ready. No speech has been requested.';
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus = NeuraAudioFocus.instance.speechActivity.listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _record(String status) {
    // Content-free receipt only. Never print a native error or spoken text.
    debugPrint('tts_smoke $status');
    if (mounted) setState(() => _status = status);
  }

  Future<void> _speak(String sample) async {
    final id = ++_request;
    _record('request=$id requested');
    try {
      await _service.speak(sample);
      _record('request=$id completed_or_cancelled');
    } catch (error) {
      _record('request=$id failure_type=${error.runtimeType}');
    }
  }

  Future<void> _stop() async {
    try {
      await _service.stop();
      _record('stop_acknowledged');
    } catch (error) {
      _record('stop_failure_type=${error.runtimeType}');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_focus?.cancel());
    unawaited(_service.stop().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Windows synthetic speech check')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: ValueListenableBuilder<bool>(
            valueListenable: SafeBoot.instance.safeMode,
            builder: (context, safeMode, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Manual diagnostics only. Check audible speech and silence. '
                  'A completed request is not proof that the native crash is fixed.',
                ),
                const SizedBox(height: 16),
                Text(_status),
                Text('Speech focus: ${NeuraAudioFocus.instance.speechActive}'),
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  FilledButton(
                    onPressed:
                        safeMode ? null : () => unawaited(_speak(_short)),
                    child: const Text('Speak short sample'),
                  ),
                  FilledButton(
                    onPressed: safeMode ? null : () => unawaited(_speak(_long)),
                    child: const Text('Speak long sample'),
                  ),
                  OutlinedButton(
                    onPressed: () => unawaited(_stop()),
                    child: const Text('Stop'),
                  ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Safe Mode'),
                  subtitle:
                      const Text('Turning this off never resumes speech.'),
                  value: safeMode,
                  onChanged: (value) {
                    SafeBoot.instance.safeMode.value = value;
                    _record('safe_mode=$value');
                  },
                ),
              ],
            ),
          ),
        ),
      );
}
