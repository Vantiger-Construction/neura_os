import 'package:flutter/material.dart';
import '../services/voice_journal_service.dart';

class VoiceJournalScreen extends StatefulWidget {
  @override
  _VoiceJournalScreenState createState() => _VoiceJournalScreenState();
}

class _VoiceJournalScreenState extends State<VoiceJournalScreen> {
  final _service = VoiceJournalService();
  bool _recording = false;
  String _transcript = '';

  void _toggleRecording() async {
    if (!_recording) {
      setState(() => _recording = true);
      await _service.startRecording();
    } else {
      final text = await _service.stopRecording();
      setState(() {
        _recording = false;
        _transcript = text;
      });
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: Text('Voice Journal')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _toggleRecording,
              child: Text(_recording ? 'Stop Recording' : 'Start Recording'),
            ),
            const SizedBox(height: 16),
            Text(_transcript.isEmpty ? 'No transcript yet.' : _transcript),
          ],
        ),
      ),
    );
  }
}
