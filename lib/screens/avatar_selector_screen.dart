import 'package:flutter/material.dart';
import '../models/ai_avatar.dart';
import '../services/avatar_service.dart';

class AvatarSelectorScreen extends StatefulWidget {
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
        children: _avatars.map((a) {
          final selected = a.id == _selectedId;
          return ListTile(
            leading: Text(a.name),
            title: Text(a.id),
            trailing: selected ? Icon(Icons.check) : null,
            onTap: () => _onSelect(a.id),
          );
        }).toList(),
      ),
    );
  }
}
