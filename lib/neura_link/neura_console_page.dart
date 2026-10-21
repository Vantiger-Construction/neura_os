import 'package:flutter/material.dart';

import 'engine_session.dart';

class NeuraConsolePage extends StatefulWidget {
  const NeuraConsolePage({super.key});

  @override
  State<NeuraConsolePage> createState() => _NeuraConsolePageState();
}

class _NeuraConsolePageState extends State<NeuraConsolePage> {
  late final EngineSession session;

  @override
  void initState() {
    super.initState();
    session = EngineSession();
  }

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  void _onLocalAcknowledged(bool? value) {
    session.acknowledgeLocalModel(value ?? false);
  }

  String _workingText() {
    if (session.mode == EngineCheckMode.local) {
      return 'Running the fixed hello on your local model. '
          'This can take up to a minute while it loads.';
    }
    return 'Checking synthetic hello and diagnostics…';
  }

  String _idleText() {
    if (session.mode == EngineCheckMode.local) {
      return 'Idle. Your local model answered the fixed hello. '
          'Nothing was kept or sent anywhere.';
    }
    return 'Idle. Hello and diagnostics verified. Echo adapter: degraded.';
  }

  String _modelUnavailableText() {
    return 'Your local model could not be verified. Use Ollama 0.18.0 or newer '
        'with the reviewed qwen3:4b-instruct model installed, then try again. '
        'Neura never downloads models or falls back to a cloud service.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Neura Engine Console')),
        body: ListenableBuilder(
          listenable: session,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Synthetic session',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'On Windows, Start checks a fixed hello and local diagnostics '
                'using the built-in echo adapter.',
              ),
              const SizedBox(height: 16),
              Text(switch (session.state) {
                EngineSessionState.disabled =>
                  'Disabled. Start creates a fresh session.',
                EngineSessionState.starting =>
                  'Starting the local synthetic session…',
                EngineSessionState.working => _workingText(),
                EngineSessionState.idle => _idleText(),
                EngineSessionState.paused =>
                  'Paused. Pending work was discarded. Resume starts a fresh check.',
                EngineSessionState.error =>
                  'The synthetic session failed and was stopped.',
                EngineSessionState.unavailable =>
                  'The Windows synthetic sidecar is unavailable.',
                EngineSessionState.blocked =>
                  'Session blocked by Safe Mode, recovery, or window lifecycle.',
                EngineSessionState.modelUnavailable => _modelUnavailableText(),
              }),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    onPressed: session.canStart ? session.start : null,
                    child: const Text('Start synthetic check'),
                  ),
                  OutlinedButton(
                    onPressed: session.canPause ? session.pause : null,
                    child: const Text('Pause'),
                  ),
                  OutlinedButton(
                    onPressed: session.canResume ? session.resume : null,
                    child: const Text('Resume'),
                  ),
                  OutlinedButton(
                    onPressed: session.stop,
                    child: const Text('Stop'),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Text(
                'Local model (optional)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Runs the same fixed hello on the qwen3:4b-instruct model in '
                'your own Ollama on this PC. Only that fixed prompt is sent; '
                'no personal data, chat or memory is used, and the reply is '
                'not kept.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: session.localAcknowledged,
                onChanged: session.canStart ? _onLocalAcknowledged : null,
                title: const Text(
                  'I installed this model myself and want the check to use it. '
                  'Nothing is downloaded and nothing leaves this computer.',
                ),
              ),
              FilledButton.tonal(
                onPressed: session.canStartLocal ? session.startLocal : null,
                child: const Text('Start local model check'),
              ),
              const SizedBox(height: 24),
              const Text(
                'One fixed check runs at a time with no waiting queue. '
                'Time or response limits pause the session. Idle runs no checks.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Closing this screen, leaving the foreground, Safe Mode, or '
                'recovery ends the session. Start is always an explicit choice.',
              ),
            ],
          ),
        ),
      );
}
