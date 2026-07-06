import 'package:flutter/material.dart';
import '../models/ai_avatar.dart';
import '../services/dual_chat_service.dart';
import '../services/avatar_service.dart';

class DualChatScreen extends StatefulWidget {
  const DualChatScreen({super.key});

  @override
  _DualChatScreenState createState() => _DualChatScreenState();
}

class _DualChatScreenState extends State<DualChatScreen> {
  final _avatarService = AvatarService();
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
      if (mounted) setState(() => _current = a);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _current == null) return;
    setState(() {
      _messages.add('You: \$text');
      _controller.clear();
    });
    final response = await _chatService.sendMessage(text, _current!);
    setState(() => _messages.add(response));
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
          )),
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
