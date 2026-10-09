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
                'On Windows, Start checks a fixed hello and local diagnostics. '
                'The model adapter remains the local echo prototype.',
              ),
              const SizedBox(height: 16),
              Text(switch (session.state) {
                EngineSessionState.disabled =>
                  'Disabled. Start creates a fresh session.',
                EngineSessionState.starting =>
                  'Starting the local synthetic session…',
                EngineSessionState.working =>
                  'Checking synthetic hello and diagnostics…',
                EngineSessionState.idle =>
                  'Idle. Hello and diagnostics verified. Echo adapter: degraded.',
                EngineSessionState.paused =>
                  'Paused. Pending work was discarded. Resume starts a fresh check.',
                EngineSessionState.error =>
                  'The synthetic session failed and was stopped.',
                EngineSessionState.unavailable =>
                  'The Windows synthetic sidecar is unavailable.',
                EngineSessionState.blocked =>
                  'Session blocked by Safe Mode, recovery, or window lifecycle.',
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
