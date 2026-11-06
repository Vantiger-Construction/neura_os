import 'package:flutter/material.dart';
import '../avatar/avatar_globals.dart';
import '../avatar/avatar_registry.dart';
import '../avatar/renderers/flutter_mouth_avatar_view.dart';
import '../models/ai_avatar.dart';
import '../services/avatar_service.dart';
import 'neura_speech_prototype_screen.dart';

class AvatarSelectorScreen extends StatefulWidget {
  const AvatarSelectorScreen({super.key});

  @override
  _AvatarSelectorScreenState createState() => _AvatarSelectorScreenState();
}

class _AvatarSelectorScreenState extends State<AvatarSelectorScreen> {
  final _service = AvatarService.instance;
  late List<AIAvatar> _avatars;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _avatars = _service.getAvailableAvatars();
    _load();
  }

  Future<void> _load() async {
    try {
      await _service.getSelectedAvatar();
    } catch (_) {
      _error =
          'Could not load your avatar. Please reopen this screen to retry.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _onSelect(String id) async {
    if (_saving || _loading) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await _service.selectAvatar(id);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!saved) _error = 'Could not save your avatar. Please try again.';
    });
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Avatar')),
      body: ValueListenableBuilder<String>(
        valueListenable: _service.selectedAvatarId,
        builder: (_, selectedId, __) => ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Choose Neura’s appearance in the app. Your choice is '
                  'saved on this device. The floating desktop mascot keeps its '
                  'original artwork.'),
            ),
            if (_loading || _saving) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, semanticsLabel: _error),
              ),
            ..._avatars.map((a) {
              final expressive = a.id == AvatarRegistry.expressiveFaceId;
              final selected = a.id == selectedId;
              return ListTile(
                key: ValueKey(a.id),
                leading: expressive
                    ? FlutterMouthAvatarView(
                        controller: AvatarGlobals.controller,
                        size: 48,
                        enabled: false,
                      )
                    : const Icon(Icons.person_outline),
                title: Text(a.name),
                subtitle: Text(expressive
                    ? 'A simple face with live speech mouth movements. '
                        'Windows uses local speech timing.'
                    : a.id == AvatarRegistry.defaultAvatarId
                        ? 'Original full-body artwork with gentle body motion.'
                        : 'Alternate identity; currently uses Neura’s fallback artwork.'),
                selected: selected,
                trailing: selected ? const Icon(Icons.check) : null,
                onTap: _loading || _saving ? null : () => _onSelect(a.id),
              );
            }),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.record_voice_over),
              title: const Text('Try local speech'),
              subtitle: const Text(
                  'Play a sample with the expressive face on Windows.'),
              onTap: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                builder: (_) => const NeuraSpeechPrototypeScreen(),
              )),
            ),
          ],
        ),
      ),
    );
  }
}
