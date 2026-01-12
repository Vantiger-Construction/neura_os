import 'package:flutter/material.dart';

import '../core/ai_engine.dart';
import '../core/app_log.dart';

class NeuraChatScreen extends StatefulWidget {
  const NeuraChatScreen({super.key});

  @override
  State<NeuraChatScreen> createState() => _NeuraChatScreenState();
}

class _NeuraChatScreenState extends State<NeuraChatScreen> {
  final _controller = TextEditingController();
  final List<_ChatLine> _lines = [
    _ChatLine.bot(
        'Hi. I’m Neura. Tell me what’s up — we’ll make a plan or we’ll breathe first.'),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _lines.add(_ChatLine.user(text));
      final reply = NeuraAICore.instance.respond(text);
      _lines.add(_ChatLine.bot(reply));
    });
    _controller.clear();
    AppLog.instance.info('chat_turn', {'user': text});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Neura Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _lines.length,
              itemBuilder: (context, i) {
                final line = _lines[i];
                final align =
                    line.isUser ? Alignment.centerRight : Alignment.centerLeft;
                final color = line.isUser
                    ? Colors.blueGrey.shade700
                    : Colors.grey.shade800;
                return Align(
                  alignment: align,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 560),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(line.text),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Talk to Neura…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatLine {
  final bool isUser;
  final String text;
  _ChatLine(this.isUser, this.text);
  factory _ChatLine.user(String t) => _ChatLine(true, t);
  factory _ChatLine.bot(String t) => _ChatLine(false, t);
}
