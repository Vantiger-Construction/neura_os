import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/neura_ai_service.dart';
import '../../services/neura_tone_check.dart';
import '../../widgets/neura_cloud_request_preview.dart';

/// Before you send: a tone check on this device, and on request a calmer
/// version. Nothing is saved; the user copies whichever version they want.
class NeuraBeforeSendScreen extends StatefulWidget {
  const NeuraBeforeSendScreen({
    super.key,
    required this.localOllama,
    this.aiService,
  });

  final bool localOllama;
  final NeuraAiService? aiService;

  static const maxLength = 2000;

  @override
  State<NeuraBeforeSendScreen> createState() => _NeuraBeforeSendScreenState();
}

class _NeuraBeforeSendScreenState extends State<NeuraBeforeSendScreen> {
  final _message = TextEditingController();
  final _to = TextEditingController();
  List<String>? _notes;
  String? _suggestion;
  bool _busy = false;

  NeuraAiService get _ai => widget.aiService ?? NeuraAiService.instance;

  @override
  void dispose() {
    _message.dispose();
    _to.dispose();
    super.dispose();
  }

  void _check() {
    setState(() {
      _notes = NeuraToneCheck.observe(_message.text);
      _suggestion = null;
    });
  }

  Future<void> _rewrite() async {
    final text = _message.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final turn = await _ai.rehearsalTurn(
        system: NeuraToneCheck.rewriteSystem,
        messages: [
          {
            'role': 'user',
            'content': NeuraToneCheck.rewriteRequest(text, to: _to.text),
          },
        ],
        localOllama: widget.localOllama,
        requestCloudApproval: (preview) => mounted
            ? showNeuraCloudRequestPreview(context, preview)
            : Future.value(false),
      );
      if (!mounted) return;
      if (turn.blocked) {
        // The guardrails answered instead: show that, never as a rewrite.
        setState(() => _suggestion = null);
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(turn.text),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return;
      }
      setState(() => _suggestion = turn.text);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.localOllama
              ? 'A rewrite is unavailable. Check that Ollama is open.'
              : 'A rewrite is unavailable right now.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = _notes;
    return Scaffold(
      appBar: AppBar(title: const Text('Before you send')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              "Paste a message you're about to send. I'll tell you how it "
              'might land. Nothing here is saved.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('before-send-to'),
              controller: _to,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Who is it for? (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('before-send-message'),
              controller: _message,
              minLines: 4,
              maxLines: 10,
              maxLength: NeuraBeforeSendScreen.maxLength,
              onChanged: (_) {
                if (_notes != null) setState(() => _notes = null);
              },
              decoration: const InputDecoration(
                labelText: 'Your message',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('before-send-check'),
              onPressed: _check,
              icon: const Icon(Icons.spellcheck),
              label: const Text('How might it land?'),
            ),
            if (notes != null) ...[
              const SizedBox(height: 16),
              if (notes.isEmpty)
                const ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('It reads clearly and calmly to me.'),
                )
              else
                for (final note in notes)
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(note),
                  ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  key: const Key('before-send-rewrite'),
                  onPressed: _busy ? null : _rewrite,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Suggest a calmer version'),
                ),
                OutlinedButton(
                  onPressed: () => _copy(_message.text, 'Your message'),
                  child: const Text('Copy mine'),
                ),
              ]),
              if (_busy) const LinearProgressIndicator(),
            ],
            if (_suggestion != null)
              Card(
                margin: const EdgeInsets.only(top: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('A calmer version',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      SelectableText(_suggestion!),
                      const SizedBox(height: 8),
                      Text(
                        'Check it still says what you mean. You choose what '
                        'to send.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () => _copy(_suggestion!, 'Suggestion'),
                        child: const Text('Copy this version'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
