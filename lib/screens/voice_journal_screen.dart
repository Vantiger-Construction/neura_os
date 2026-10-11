import 'dart:async';

import 'package:flutter/material.dart';

import '../reliability/safe_boot.dart';
import '../services/local_journal_store.dart';
import '../services/neura_companion_presence.dart';
import '../services/voice_journal_service.dart';

class VoiceJournalScreen extends StatefulWidget {
  const VoiceJournalScreen({super.key});

  @override
  State<VoiceJournalScreen> createState() => _VoiceJournalScreenState();
}

class _VoiceJournalScreenState extends State<VoiceJournalScreen> {
  final VoiceJournalService _service = VoiceJournalService();
  final LocalJournalStore _journalStore = LocalJournalStore();
  final TextEditingController _controller = TextEditingController();
  StreamSubscription<String>? _sub;

  bool _recording = false;
  String _transcript = '';
  String _draftId = _newDraftId();
  bool _saving = false;
  String? _saveStatus;

  @override
  void initState() {
    super.initState();
    _recording = _service.recording.value;
    _service.recording.addListener(_onRecordingChanged);
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
    _sub = _service.transcriptStream.listen((text) {
      if (!mounted) return;
      setState(() {
        _transcript = text;
        _controller.text = text;
        _saveStatus = null;
      });
    });
  }

  void _onRecordingChanged() {
    if (!mounted) return;
    setState(() => _recording = _service.recording.value);
  }

  void _onSafeModeChanged() {
    if (!mounted) return;
    setState(() {
      if (SafeBoot.instance.safeMode.value) _recording = false;
    });
  }

  @override
  void dispose() {
    _service.recording.removeListener(_onRecordingChanged);
    SafeBoot.instance.safeMode.removeListener(_onSafeModeChanged);
    _sub?.cancel();
    unawaited(_service.dispose());
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (SafeBoot.instance.safeMode.value) return;
    if (!_recording) {
      if (_controller.text.trim().isEmpty || _saveStatus != null) {
        _draftId = _newDraftId();
      }
      await _service.startRecording();
    } else {
      final text = await _service.stopRecording();
      if (!mounted) return;
      setState(() {
        _transcript = text;
        _controller.text = text;
      });
    }
  }

  Future<void> _saveTranscript() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _saveStatus = null;
    });
    try {
      await _journalStore.upsertEntry(
        id: _draftId,
        content: text,
        isVoice: true,
      );
      if (!mounted) return;
      setState(() => _saveStatus = 'Saved to your local journal.');
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _saveStatus = 'Could not save. Your transcript is still here.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeMode = SafeBoot.instance.safeMode.value;
    final colors = Theme.of(context).colorScheme;

    return ValueListenableBuilder<NeuraPresenceSnapshot>(
      valueListenable: NeuraCompanionPresence.instance.state,
      builder: (context, presence, _) {
        final statusColor = safeMode
            ? colors.error
            : presence.microphoneActive
            ? colors.primary
            : colors.secondary;
        return Scaffold(
          appBar: AppBar(title: const Text('Voice Journal')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: statusColor.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          safeMode
                              ? Icons.shield_outlined
                              : presence.microphoneActive
                              ? Icons.graphic_eq
                              : Icons.favorite_outline,
                          color: statusColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                safeMode
                                    ? 'Safe Mode · microphone is off'
                                    : presence.label,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                safeMode
                                    ? 'Voice stays unavailable until the next normal launch.'
                                    : 'Transcript text stays in this local journal session.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Neura does not upload this transcript to a cloud service.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: safeMode ? null : _toggleRecording,
                  icon: Icon(_recording ? Icons.stop : Icons.mic_none),
                  label: Text(
                    _recording ? 'Stop listening' : 'Start listening',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Local transcript',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _controller,
                        minLines: 8,
                        maxLines: null,
                        decoration: InputDecoration(
                          hintText: _transcript.isEmpty
                              ? 'No local transcript yet.'
                              : null,
                          border: InputBorder.none,
                        ),
                        onChanged: (_) => setState(() => _saveStatus = null),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed:
                      safeMode ||
                          _recording ||
                          _saving ||
                          _controller.text.trim().isEmpty
                      ? null
                      : _saveTranscript,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving' : 'Save to journal'),
                ),
                if (_saveStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(_saveStatus!, textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static String _newDraftId() =>
      'voice_journal_${DateTime.now().toUtc().toIso8601String()}';
}
