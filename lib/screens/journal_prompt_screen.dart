import 'package:flutter/material.dart';
import '../services/local_journal_store.dart';
import '../services/journal_prompt_service.dart';

class JournalPromptScreen extends StatefulWidget {
  const JournalPromptScreen({
    super.key,
    JournalPromptService? promptService,
    LocalJournalStore? journalStore,
    DateTime Function()? now,
  })  : _promptService = promptService,
        _journalStore = journalStore,
        _now = now;

  final JournalPromptService? _promptService;
  final LocalJournalStore? _journalStore;
  final DateTime Function()? _now;

  @override
  State<JournalPromptScreen> createState() => _JournalPromptScreenState();
}

class _JournalPromptScreenState extends State<JournalPromptScreen> {
  late final JournalPromptService _service =
      widget._promptService ?? JournalPromptService();
  late final DateTime Function() _now = widget._now ?? DateTime.now;
  late final LocalJournalStore _journalStore =
      widget._journalStore ?? LocalJournalStore(now: _now);
  final TextEditingController _controller = TextEditingController();

  String _prompt = '';
  String _entryId = '';
  bool _loading = true;
  bool _saving = false;
  String? _status;

  Future<void> _loadPrompt() async {
    final now = _now();
    final prompt = await _service.fetchPrompt(time: now);
    final entryId = _promptEntryId(now);
    final existing = await _journalStore.findById(entryId);
    if (!mounted) return;
    _controller.text = existing == null
        ? ''
        : _JournalPromptEntryCodec.responseFrom(existing.content);
    setState(() {
      _prompt = prompt;
      _entryId = entryId;
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

  Future<void> _saveResponse() async {
    final response = _controller.text.trim();
    if (response.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      await _journalStore.upsertEntry(
        id: _entryId,
        timestamp: _now(),
        content: _JournalPromptEntryCodec.encode(
          prompt: _prompt,
          response: response,
        ),
      );
      if (!mounted) return;
      setState(() => _status = 'Saved to your local journal.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Could not save. Your draft is still here.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
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
                  minLines: 8,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Write a response',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _status = null),
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
                if (_status != null) ...[
                  const SizedBox(height: 8),
                  Text(_status!, textAlign: TextAlign.center),
                ],
              ],
            ),
    );
  }

  String _promptEntryId(DateTime time) {
    final local = DateTime(time.year, time.month, time.day);
    final part = local.toIso8601String().substring(0, 10);
    return 'journal_prompt_$part';
  }
}

final class _JournalPromptEntryCodec {
  static const _prefix = 'Prompt:\n';
  static const _separator = '\n\nResponse:\n';

  static String encode({required String prompt, required String response}) =>
      '$_prefix$prompt$_separator$response';

  static String responseFrom(String content) {
    final index = content.indexOf(_separator);
    if (content.startsWith(_prefix) && index != -1) {
      return content.substring(index + _separator.length);
    }
    return content;
  }
}
