import 'package:flutter/material.dart';

import '../../persona/models/neura_audience.dart';
import '../../persona/services/neura_prompt_builder.dart';

/// Simple stub for a Neura "kids chat" screen. This does NOT call a real LLM;
/// it just shows the prompt that would be sent so you can wire your backend.
class KidsNeuraChatStubScreen extends StatefulWidget {
  const KidsNeuraChatStubScreen({Key? key}) : super(key: key);

  @override
  State<KidsNeuraChatStubScreen> createState() => _KidsNeuraChatStubScreenState();
}

class _KidsNeuraChatStubScreenState extends State<KidsNeuraChatStubScreen> {
  final TextEditingController _controller = TextEditingController();
  String _lastPrompt = '';
  bool _loading = false;

  Future<void> _onSend() async {
    final userText = _controller.text.trim();
    if (userText.isEmpty) return;

    setState(() {
      _loading = true;
      _lastPrompt = '';
    });

    final promptBuilder = NeuraPromptBuilder.instance;
    final systemMessage = await promptBuilder.buildSystemMessage(
      module: 'kids_mode',
      audience: NeuraAudience.child,
    );

    // In your real app, you would send systemMessage + userText to your backend here.
    // For now we just show the systemMessage so you can inspect the safety text.
    if (!mounted) return;
    setState(() {
      _loading = false;
      _lastPrompt = systemMessage;
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neura Kids Chat (Stub)'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'This is a kids-safe Neura chat stub.\n'
              'Messages here will use a child-appropriate system prompt.\n'
              'You still need to wire this to your backend LLM.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Type something a child might say...',
                    ),
                    onSubmitted: (_) => _onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _onSend,
                      ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Generated kids-safe system prompt (for debugging):',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8.0),
              child: SelectableText(
                _lastPrompt.isEmpty
                    ? 'Send a message to see the system prompt that would be used.'
                    : _lastPrompt,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
