import 'package:flutter/material.dart';

import '../../core/memory/memory_graph_service.dart';
import '../core/app_log.dart';
import 'therapy_models.dart';
import 'therapy_response_store.dart';

/// Write a reflection for one [TherapyPrompt], and browse past responses to
/// it. Saved responses are encrypted at rest (see [TherapyResponseStore])
/// and also logged to [MemoryGraphService] - a completed reflection is
/// exactly the kind of thing worth Neura remembering.
class TherapyReflectionScreen extends StatefulWidget {
  final TherapyPrompt prompt;

  const TherapyReflectionScreen({super.key, required this.prompt});

  @override
  State<TherapyReflectionScreen> createState() =>
      _TherapyReflectionScreenState();
}

class _TherapyReflectionScreenState extends State<TherapyReflectionScreen> {
  final _controller = TextEditingController();
  List<TherapyResponse> _past = const [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final past = await TherapyResponseStore.I.forPrompt(widget.prompt.id);
    if (!mounted) return;
    setState(() {
      _past = past;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final saved =
          await TherapyResponseStore.I.save(prompt: widget.prompt, text: text);
      try {
        await MemoryGraphService.I.logUserAction(
          kind: 'THERAPY_REFLECTION',
          payload: {
            'method': widget.prompt.method,
            'promptTitle': widget.prompt.title,
            'text': text,
          },
        );
      } catch (e, st) {
        await AppLog.instance.caught('therapy_memory_log_failed', e, st);
      }
      if (!mounted) return;
      setState(() {
        _past = [saved, ..._past];
        _controller.clear();
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.prompt.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.prompt.instruction,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Write your reflection…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save reflection'),
              ),
            ),
            const SizedBox(height: 20),
            Text('Past reflections',
                style: Theme.of(context).textTheme.titleSmall),
            const Divider(),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_past.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Nothing saved yet for this prompt.'),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _past.length,
                  itemBuilder: (context, i) {
                    final r = _past[i];
                    return Card(
                      child: ListTile(
                        title: Text(r.text),
                        subtitle: Text(_formatTimestamp(r.timestamp)),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _twoDigits(int n) => n.toString().padLeft(2, '0');

  String _formatTimestamp(DateTime t) {
    final local = t.toLocal();
    return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} '
        '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
  }
}
