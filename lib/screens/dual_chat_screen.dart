import 'package:flutter/material.dart';

import '../avatar/avatar_globals.dart';
import '../models/ai_avatar.dart';
import '../services/dual_chat_service.dart';
import '../services/avatar_service.dart';

class DualChatScreen extends StatefulWidget {
  const DualChatScreen({super.key});

  @override
  _DualChatScreenState createState() => _DualChatScreenState();
}

class _DualChatScreenState extends State<DualChatScreen> {
  final _avatarService = AvatarService.instance;
  final _chatService = DualChatService();
  List<AIAvatar> _avatars = [];
  AIAvatar? _current;
  final _controller = TextEditingController();
  final List<String> _messages = [];

  @override
  void initState() {
    super.initState();
    _avatars = _avatarService.getAvailableAvatars();
    _avatarService.getSelectedAvatar().then((a) {
      setState(() => _current = a);
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _current == null) return;

    setState(() {
      _messages.add('You: $text');
      _controller.clear();
    });

    AvatarGlobals.controller.setThinking(true);
    try {
      final response = await _chatService.sendMessage(text, _current!);
      setState(() => _messages.add(response));
    } finally {
      AvatarGlobals.controller.setThinking(false);
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat with AI'),
        actions: [
          PopupMenuButton<AIAvatar>(
            onSelected: (a) => setState(() => _current = a),
            itemBuilder: (_) => _avatars
                .map((a) => PopupMenuItem(value: a, child: Text(a.name)))
                .toList(),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: _messages.map((m) => ListTile(title: Text(m))).toList(),
            ),
          ),
          Divider(),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _controller)),
                IconButton(icon: Icon(Icons.send), onPressed: _send),
              ],
            ),
          )
        ],
      ),
    );
  }
}
