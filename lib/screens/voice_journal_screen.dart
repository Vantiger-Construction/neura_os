import 'dart:async';

import 'package:flutter/material.dart';

import '../models/journal_entry.dart';
import '../reliability/safe_boot.dart';
import '../services/local_journal_store.dart';
import '../services/neura_companion_presence.dart';
import '../services/voice_journal_service.dart';

class VoiceJournalScreen extends StatefulWidget {
  const VoiceJournalScreen({
    super.key,
    LocalJournalStore? journalStore,
    VoiceJournalService? service,
  })  : _journalStore = journalStore,
        _service = service;

  final LocalJournalStore? _journalStore;
  final VoiceJournalService? _service;

  @override
  State<VoiceJournalScreen> createState() => _VoiceJournalScreenState();
}

class _VoiceJournalScreenState extends State<VoiceJournalScreen> {
  late final VoiceJournalService _service =
      widget._service ?? VoiceJournalService();
  late final LocalJournalStore _journalStore =
      widget._journalStore ?? LocalJournalStore();
  final TextEditingController _controller = TextEditingController();
  StreamSubscription<String>? _sub;

  bool _recording = false;
  String _transcript = '';
  String _draftId = LocalJournalStore.newEntryId('voice_journal');
  String _savedTranscript = '';
  List<JournalEntry> _history = const [];
  int _draftRevision = 0;
  bool _saving = false;
  bool _captureBusy = false;
  bool _stoppingCapture = false;
  int _captureGeneration = 0;
  String? _saveStatus;

  bool get _hasUnsavedDraft => _controller.text.trim() != _savedTranscript;
  bool get _captureLocked => _recording || _captureBusy;

  @override
  void initState() {
    super.initState();
    _recording = _service.recording.value;
    _service.recording.addListener(_onRecordingChanged);
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
    _sub = _service.transcriptStream.listen((text) {
      if (!mounted) return;
      if (_isVoiceStatusMessage(text)) {
        setState(() {
          _saveStatus = text;
          if (!_service.isListening) {
            _recording = false;
            _captureBusy = false;
            _stoppingCapture = false;
            _captureGeneration++;
          }
        });
        return;
      }
      if (!_recording || _captureBusy || !_service.recording.value) {
        return;
      }
      setState(() {
        _transcript = text;
        _controller.text = text;
        _draftRevision++;
        _saveStatus = null;
      });
    });
    unawaited(_refreshHistory());
  }

  void _onRecordingChanged() {
    if (!mounted) return;
    setState(() => _recording = _service.recording.value);
  }

  void _onSafeModeChanged() {
    if (!mounted) return;
    setState(() {
      if (SafeBoot.instance.safeMode.value) {
        _recording = false;
        _captureBusy = false;
        _stoppingCapture = false;
        _captureGeneration++;
      }
    });
  }

  @override
  void dispose() {
    _captureGeneration++;
    _service.recording.removeListener(_onRecordingChanged);
    SafeBoot.instance.safeMode.removeListener(_onSafeModeChanged);
    _sub?.cancel();
    unawaited(_service.dispose());
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (SafeBoot.instance.safeMode.value || _captureBusy) return;
    final generation = ++_captureGeneration;
    if (!_recording) {
      setState(() {
        _captureBusy = true;
        _stoppingCapture = false;
        if (_controller.text.trim().isEmpty || _saveStatus != null) {
          _draftId = LocalJournalStore.newEntryId('voice_journal');
          _savedTranscript = '';
        }
      });
      final started = await _service.startRecording();
      if (!mounted || generation != _captureGeneration) return;
      setState(() {
        _captureBusy = false;
        _recording = started && _service.recording.value;
        if (!started) {
          _saveStatus ??= 'Voice input could not start on this device.';
        }
      });
    } else {
      setState(() {
        _captureBusy = true;
        _stoppingCapture = true;
      });
      final text = await _service.stopRecording();
      if (!mounted || generation != _captureGeneration) return;
      setState(() {
        _captureBusy = false;
        _stoppingCapture = false;
        _recording = false;
        if (text.trim().isNotEmpty && !_isVoiceStatusMessage(text)) {
          _transcript = text;
          _controller.text = text;
          _draftRevision++;
        }
      });
    }
  }

  Future<void> _refreshHistory() async {
    final history = await _journalStore.findAll(isVoice: true);
    if (!mounted) return;
    setState(() => _history = history);
  }

  Future<void> _saveTranscript() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving || _captureLocked) return;
    final savedRevision = _draftRevision;
    final draftId = _draftId;
    setState(() {
      _saving = true;
      _saveStatus = null;
    });
    try {
      await _journalStore.upsertEntry(
        id: draftId,
        content: text,
        isVoice: true,
      );
      if (!mounted) return;
      final history = await _journalStore.findAll(isVoice: true);
      if (!mounted) return;
      setState(() {
        _history = history;
        if (_draftRevision == savedRevision &&
            _controller.text.trim() == text) {
          _savedTranscript = text;
          _saveStatus = 'Saved to your local journal.';
        } else {
          _saveStatus = 'Saved earlier transcript. Unsaved edits remain.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _saveStatus = 'Could not save. Your transcript is still here.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSavedTranscript(JournalEntry entry) async {
    if (_captureLocked) return;
    if (_hasUnsavedDraft && !await _confirmDiscardDraft()) return;
    _controller.text = entry.content;
    if (!mounted) return;
    setState(() {
      _draftId = entry.id;
      _transcript = entry.content;
      _savedTranscript = entry.content;
      _draftRevision++;
      _saveStatus = 'Saved transcript reopened.';
    });
  }

  Future<void> _showAllSavedTranscripts() async {
    if (_captureLocked) return;
    final selected = await showModalBottomSheet<JournalEntry>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView.builder(
          itemCount: _history.length,
          itemBuilder: (context, index) {
            final entry = _history[index];
            return ListTile(
              leading: const Icon(Icons.history_outlined),
              title: Text(_historyLabel(entry)),
              onTap: () => Navigator.of(context).pop(entry),
            );
          },
        ),
      ),
    );
    if (selected != null) await _openSavedTranscript(selected);
  }

  void _discardDraft() {
    if (_captureLocked) return;
    _controller.text = _savedTranscript;
    setState(() {
      _transcript = _savedTranscript;
      _draftRevision++;
      _saveStatus =
          _savedTranscript.isEmpty ? null : 'Saved transcript reopened.';
    });
  }

  Future<bool> _confirmDiscardDraft() async {
    if (!_hasUnsavedDraft) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved transcript?'),
        content: const Text('Your current transcript has not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  bool _isVoiceStatusMessage(String text) =>
      text.startsWith('Microphone ') || text.startsWith('Speech-to-text ');

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
        return PopScope(
          canPop: !_hasUnsavedDraft && !_saving && !_captureLocked,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (_captureLocked) return;
            if (await _confirmDiscardDraft() && mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(title: const Text('Voice Journal')),
            body: ListView(
              padding: const EdgeInsets.all(16),
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
                  onPressed: safeMode || _captureBusy ? null : _toggleRecording,
                  icon: _captureBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_recording ? Icons.stop : Icons.mic_none),
                  label: Text(
                    _captureBusy
                        ? (_stoppingCapture ? 'Stopping' : 'Starting')
                        : _recording
                            ? 'Stop listening'
                            : 'Start listening',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Local transcript',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _controller,
                      enabled: !_saving && !_captureBusy,
                      minLines: 8,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: _transcript.isEmpty
                            ? 'No local transcript yet.'
                            : null,
                        border: InputBorder.none,
                      ),
                      onChanged: (value) => setState(() {
                        _transcript = value;
                        _draftRevision++;
                        _saveStatus = null;
                      }),
                    ),
                  ),
                ),
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Saved transcripts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final entry in _history.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: _saving || _captureLocked
                            ? null
                            : () => _openSavedTranscript(entry),
                        icon: const Icon(Icons.history_outlined),
                        label: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _historyLabel(entry),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  if (_history.length > 8)
                    TextButton.icon(
                      onPressed: _saving || _captureLocked
                          ? null
                          : _showAllSavedTranscripts,
                      icon: const Icon(Icons.list_alt_outlined),
                      label: const Text('Show all saved transcripts'),
                    ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: safeMode ||
                          _captureLocked ||
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
                if (_hasUnsavedDraft) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _saving || _captureLocked ? null : _discardDraft,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Discard draft'),
                  ),
                ],
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

  static String _historyLabel(JournalEntry entry) {
    final date = LocalJournalStore.datePart(entry.timestamp);
    final excerpt = entry.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (excerpt.isEmpty) return date;
    return '$date - ${excerpt.length > 48 ? '${excerpt.substring(0, 48)}...' : excerpt}';
  }
}
