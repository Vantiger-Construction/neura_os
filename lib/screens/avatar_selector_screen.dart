import 'package:flutter/material.dart';
import '../models/ai_avatar.dart';
import '../services/avatar_service.dart';
import 'neura_speech_prototype_screen.dart';

class AvatarSelectorScreen extends StatefulWidget {
  const AvatarSelectorScreen({super.key});

  @override
  _AvatarSelectorScreenState createState() => _AvatarSelectorScreenState();
}

class _AvatarSelectorScreenState extends State<AvatarSelectorScreen> {
  final _service = AvatarService();
  late List<AIAvatar> _avatars;
  String _selectedId = '';

  @override
  void initState() {
    super.initState();
    _avatars = _service.getAvailableAvatars();
    _service.getSelectedAvatar().then((avatar) {
      if (!mounted) return;
      setState(() => _selectedId = avatar.id);
    });
  }

  void _onSelect(String id) {
    setState(() => _selectedId = id);
    _service.selectAvatar(id);
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: Text('Select Avatar')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.record_voice_over),
            title: const Text('Neura speech prototype'),
            onTap: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
              builder: (_) => const NeuraSpeechPrototypeScreen(),
            )),
          ),
          ..._avatars.map((a) {
            final selected = a.id == _selectedId;
            return ListTile(
              leading: Text(a.name),
              title: Text(a.id),
              trailing: selected ? Icon(Icons.check) : null,
              onTap: () => _onSelect(a.id),
            );
          }),
        ],
      ),
    );
  }
}
