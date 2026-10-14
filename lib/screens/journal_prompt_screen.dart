import 'package:flutter/material.dart';
import '../models/journal_entry.dart';
import '../services/local_journal_store.dart';
import '../services/journal_prompt_service.dart';

class JournalPromptScreen extends StatefulWidget {
  const JournalPromptScreen({
    super.key,
    JournalPromptService? promptService,
    LocalJournalStore? journalStore,
    DateTime Function()? now,
    String Function(DateTime time)? entryIdFactory,
  })  : _promptService = promptService,
        _journalStore = journalStore,
        _now = now,
        _entryIdFactory = entryIdFactory;

  final JournalPromptService? _promptService;
  final LocalJournalStore? _journalStore;
  final DateTime Function()? _now;
  final String Function(DateTime time)? _entryIdFactory;

  @override
  State<JournalPromptScreen> createState() => _JournalPromptScreenState();
}

class _JournalPromptScreenState extends State<JournalPromptScreen> {
  late final JournalPromptService _service =
      widget._promptService ?? JournalPromptService();
  late final DateTime Function() _now = widget._now ?? DateTime.now;
  late final LocalJournalStore _journalStore =
      widget._journalStore ?? LocalJournalStore(now: _now);
  late final String Function(DateTime time) _entryIdFactory =
      widget._entryIdFactory ??
          (_) => LocalJournalStore.newEntryId('journal_prompt');
  final TextEditingController _controller = TextEditingController();

  String _prompt = '';
  String _entryId = '';
  String _moodTag = '';
  String _savedResponse = '';
  List<JournalEntry> _history = const [];
  int _draftRevision = 0;
  bool _loading = true;
  bool _saving = false;
  String? _status;

  bool get _hasUnsavedDraft =>
      !_loading && _controller.text.trim() != _savedResponse;

  Future<void> _loadPrompt() async {
    final now = _now();
    final moodTag = LocalJournalStore.journalPromptMoodTag(now);
    final existing = await _journalStore.findJournalPromptForDate(now);
    final prompt = existing == null
        ? await _service.fetchPrompt(time: now)
        : _JournalPromptEntryCodec.decode(existing.content).prompt ??
            await _service.fetchPrompt(time: now);
    final entryId = existing?.id ?? _entryIdFactory(now);
    final response = existing == null
        ? ''
        : _JournalPromptEntryCodec.decode(existing.content).response;
    final history = await _loadHistory();
    if (!mounted) return;
    _controller.text = response;
    setState(() {
      _prompt = prompt;
      _entryId = entryId;
      _moodTag = moodTag;
      _savedResponse = response;
      _history = history;
      _draftRevision++;
      _loading = false;
      _status = existing == null ? null : 'Saved response reopened.';
    });
  }

  @override
  void initState() {
    super.initState();
    _loadPrompt();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<List<JournalEntry>> _loadHistory() =>
      _journalStore.findJournalPromptEntries();

  Future<void> _saveResponse() async {
    final response = _controller.text.trim();
    if (response.isEmpty || _saving) return;
    final savedRevision = _draftRevision;
    final entryId = _entryId;
    final prompt = _prompt;
    final moodTag = _moodTag;
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      await _journalStore.upsertEntry(
        id: entryId,
        timestamp: _now(),
        content: _JournalPromptEntryCodec.encode(
          prompt: prompt,
          response: response,
        ),
        moodTag: moodTag,
      );
      if (!mounted) return;
      final history = await _loadHistory();
      if (!mounted) return;
      setState(() {
        _history = history;
        if (_draftRevision == savedRevision &&
            _controller.text.trim() == response) {
          _savedResponse = response;
          _status = 'Saved to your local journal.';
        } else {
          _status = 'Saved earlier draft. Unsaved edits remain.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not save. Your draft is still here.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSavedResponse(JournalEntry entry) async {
    if (_hasUnsavedDraft && !await _confirmDiscardDraft()) return;
    final decoded = _JournalPromptEntryCodec.decode(entry.content);
    final prompt = decoded.prompt ?? _prompt;
    _controller.text = decoded.response;
    if (!mounted) return;
    setState(() {
      _prompt = prompt;
      _entryId = entry.id;
      _moodTag = LocalJournalStore.journalPromptMoodTagForEntry(entry);
      _savedResponse = decoded.response;
      _draftRevision++;
      _status = 'Saved response reopened.';
    });
  }

  Future<void> _showAllSavedResponses() async {
    final selected = await showModalBottomSheet<JournalEntry>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView.builder(
          itemCount: _history.length,
          itemBuilder: (context, index) {
            final entry = _history[index];
            return ListTile(
              leading: const Icon(Icons.history_outlined),
              title: Text(_JournalPromptEntryCodec.historyLabel(entry)),
              onTap: () => Navigator.of(context).pop(entry),
            );
          },
        ),
      ),
    );
    if (selected != null) await _openSavedResponse(selected);
  }

  void _discardDraft() {
    _controller.text = _savedResponse;
    setState(() {
      _draftRevision++;
      _status = _savedResponse.isEmpty ? null : 'Saved response reopened.';
    });
  }

  Future<bool> _confirmDiscardDraft() async {
    if (!_hasUnsavedDraft) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved draft?'),
        content: const Text('Your current journal text has not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep writing'),
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

  @override
  Widget build(BuildContext ctx) {
    return PopScope(
      canPop: !_hasUnsavedDraft && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscardDraft() && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Journal Prompt')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(_prompt, style: Theme.of(ctx).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    enabled: !_saving,
                    minLines: 8,
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Write a response',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {
                      _draftRevision++;
                      _status = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving || _controller.text.trim().isEmpty
                        ? null
                        : _saveResponse,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving' : 'Save response'),
                  ),
                  if (_hasUnsavedDraft) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _saving ? null : _discardDraft,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Discard draft'),
                    ),
                  ],
                  if (_status != null) ...[
                    const SizedBox(height: 8),
                    Text(_status!, textAlign: TextAlign.center),
                  ],
                  if (_history.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Saved responses',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final entry in _history.take(8))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton.icon(
                          onPressed:
                              _saving ? null : () => _openSavedResponse(entry),
                          icon: const Icon(Icons.history_outlined),
                          label: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _JournalPromptEntryCodec.historyLabel(entry),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    if (_history.length > 8)
                      TextButton.icon(
                        onPressed: _saving ? null : _showAllSavedResponses,
                        icon: const Icon(Icons.list_alt_outlined),
                        label: const Text('Show all saved responses'),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

final class _JournalPromptDecodedEntry {
  const _JournalPromptDecodedEntry({this.prompt, required this.response});

  final String? prompt;
  final String response;
}

final class _JournalPromptEntryCodec {
  static const _prefix = 'Prompt:\n';
  static const _separator = '\n\nResponse:\n';

  static String encode({required String prompt, required String response}) =>
      '$_prefix$prompt$_separator$response';

  static _JournalPromptDecodedEntry decode(String content) {
    final index = content.indexOf(_separator);
    if (content.startsWith(_prefix) && index != -1) {
      return _JournalPromptDecodedEntry(
        prompt: content.substring(_prefix.length, index),
        response: content.substring(index + _separator.length),
      );
    }
    return _JournalPromptDecodedEntry(response: content);
  }

  static String historyLabel(JournalEntry entry) {
    final moodTag = LocalJournalStore.journalPromptMoodTagForEntry(entry);
    final date = moodTag.substring('journal_prompt:'.length);
    final prompt = decode(entry.content).prompt;
    return prompt == null ? date : '$date - $prompt';
  }
}
