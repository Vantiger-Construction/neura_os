import 'package:flutter/material.dart';
import '../conversation_controller.dart';

class StreamingChatView extends StatefulWidget {
  const StreamingChatView({super.key, required this.controller});
  final ConversationController controller;
  @override
  State<StreamingChatView> createState() => _StreamingChatViewState();
}

class _StreamingChatViewState extends State<StreamingChatView> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    widget.controller.send(text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation:
            Listenable.merge([widget.controller, widget.controller.tone]),
        builder: (context, _) => Column(children: [
          Expanded(
              child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: widget.controller.messages.length,
                  itemBuilder: (context, index) {
                    final message = widget.controller.messages[index];
                    final mine = message.role == ConversationRole.user;
                    return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Card(
                          color: mine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${message.text}${message.streaming ? ' ▍' : ''}'),
                                    if (message.interrupted)
                                      const Padding(
                                          padding: EdgeInsets.only(top: 6),
                                          child: Text('Interrupted',
                                              style: TextStyle(fontSize: 11))),
                                  ])),
                        ));
                  })),
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                        child: TextField(
                            controller: _input,
                            onSubmitted: (_) => _send(),
                            decoration: const InputDecoration(
                                hintText: 'Talk to Neura…',
                                border: OutlineInputBorder()))),
                    const SizedBox(width: 8),
                    IconButton.filled(
                        onPressed:
                            widget.controller.link.isConnected ? _send : null,
                        icon: const Icon(Icons.send)),
                  ]))),
        ]),
      );
}
