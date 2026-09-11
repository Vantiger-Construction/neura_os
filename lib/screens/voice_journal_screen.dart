import 'dart:async';

import 'package:flutter/material.dart';

import '../services/voice_journal_service.dart';

class VoiceJournalScreen extends StatefulWidget {
  const VoiceJournalScreen({super.key});

  @override
  State<VoiceJournalScreen> createState() => _VoiceJournalScreenState();
}

class _VoiceJournalScreenState extends State<VoiceJournalScreen> {
  final VoiceJournalService _service = VoiceJournalService();
  StreamSubscription<String>? _sub;

  bool _recording = false;
  String _transcript = '';

  @override
  void initState() {
    super.initState();
    _sub = _service.transcriptStream.listen((t) {
      if (!mounted) return;
      setState(() => _transcript = t);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(_service.dispose());
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (!_recording) {
      final ok = await _service.startRecording();
      if (!mounted) return;
      if (!ok) {
        setState(() => _recording = false);
        return;
      }
      setState(() => _recording = true);
    } else {
      final text = await _service.stopRecording();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _transcript = text;
      });
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Journal')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _toggleRecording,
              icon: Icon(_recording ? Icons.stop : Icons.mic_none),
              label: Text(_recording ? 'Stop' : 'Start'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _transcript.isEmpty ? 'No transcript yet.' : _transcript,
                  style: Theme.of(ctx).textTheme.bodyLarge,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
