import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../avatar/avatar_globals.dart';
import '../avatar/avatar_registry.dart';
import '../avatar/avatar_view.dart';
import '../persona/models/neura_audience.dart';
import '../persona/models/neura_persona_preset.dart';
import '../persona/screens/persona_tuning_screen.dart';
import '../services/neura_ai_service.dart';
import '../services/neura_ollama_chat.dart';
import '../src/core/data_wipe_service.dart';
import '../widgets/neura_cloud_request_preview.dart';
import 'local_profile_service.dart';

/// No navigation to installation-wide private stores. Every selected session
/// receives a fresh widget, history, route choice and cloud approval callback.
class LocalProfileWorkspace extends StatefulWidget {
  const LocalProfileWorkspace({super.key, this.service, this.aiService});
  final LocalProfileService? service;
  final NeuraAiService? aiService;
  @override
  State<LocalProfileWorkspace> createState() => _LocalProfileWorkspaceState();
}

class _LocalProfileWorkspaceState extends State<LocalProfileWorkspace> {
  LocalProfileService get _service =>
      widget.service ?? LocalProfileService.instance;
  @override
  void initState() {
    super.initState();
    if (!_service.loaded && !_service.busy) unawaited(_service.load());
  }

  Future<void> _create() async {
    final label = TextEditingController();
    var preset = NeuraPersonaPreset.calm;
    var audience = NeuraAudience.child;
    final epoch = _service.epoch;
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                  title: const Text('New local profile'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: label,
                        maxLength: 40,
                        decoration: const InputDecoration(
                            labelText: 'Profile label (nickname)')),
                    DropdownButton<NeuraPersonaPreset>(
                        value: preset,
                        isExpanded: true,
                        items: [
                          for (final p in NeuraPersonaPreset.values)
                            DropdownMenuItem(value: p, child: Text(p.label))
                        ],
                        onChanged: (p) => setState(() => preset = p!)),
                    DropdownButton<NeuraAudience>(
                        value: audience,
                        isExpanded: true,
                        items: [
                          for (final a in NeuraAudience.values)
                            DropdownMenuItem(
                                value: a, child: Text('Age group: ${a.name}'))
                        ],
                        onChanged: (a) => setState(() => audience = a!)),
                    const Text(
                        'Only this chosen style and age group are saved. '
                        'No private conversation learning or shared memories. '
                        'Anyone with access to this app can select a profile.'),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Create profile'))
                  ],
                )));
    final name = label.text;
    // Dispose after the dialog's route animation releases its TextField.
    WidgetsBinding.instance.addPostFrameCallback((_) => label.dispose());
    if (approved == true && mounted && epoch == _service.epoch) {
      await _service.create(
          label: name,
          persona: preset.profile,
          audience: audience,
          directUserGesture: true);
    }
  }

  Future<void> _remove(LocalNeuraProfile profile) async {
    final epoch = _service.epoch;
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('Remove ${profile.label}?'),
                content: const Text(
                    'Removes this saved style and ends the current chat. '
                    'Other profiles are kept. This does not erase installation-wide data.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Remove profile'))
                ]));
    if (approved == true && mounted && epoch == _service.epoch) {
      await _service.remove(profile.id, directUserGesture: true);
    }
  }

  Future<void> _wipe() async {
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Erase all local Neura data?'),
                content: const Text(
                    'Deletes every profile and all existing installation data, '
                    'including journals, vaults and credentials. This cannot be undone.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Erase all local data'))
                ]));
    if (approved != true || !mounted) return;
    try {
      await NeuraDataWipeService.wipeAllLocalData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Local data erased. Restart Neura.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Removal is incomplete. Keep Neura closed and retry local-data removal.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final active = _service.active;
        if (active != null && !_service.busy) {
          return _ProfileChat(
              key: ValueKey(_service.epoch),
              service: _service,
              ai: widget.aiService ?? NeuraAiService.instance);
        }
        return PopScope(
            canPop: false,
            child: Scaffold(
              appBar: AppBar(
                  title: const Text('Choose a local profile'),
                  automaticallyImplyLeading: false),
              body: ListView(padding: const EdgeInsets.all(16), children: [
                const Text(
                    'Profiles keep chosen styles separate on this device. '
                    'Selection is not a password or proof of identity. '
                    'Chats are temporary. Memories, journals, tools, sync and voice permissions '
                    'are unavailable in this first profile workspace.'),
                if (_service.busy) const LinearProgressIndicator(),
                if (_service.error != null) ...[
                  Text(_service.error!),
                  TextButton(
                      onPressed: _service.busy ? null : _service.load,
                      child: const Text('Reload saved profiles')),
                ],
                for (final profile in _service.profiles)
                  ListTile(
                      title: Text(profile.label),
                      subtitle: Text('Age group: ${profile.audience.name}'),
                      onTap: _service.busy
                          ? null
                          : () => _service.select(profile.id,
                              directUserGesture: true),
                      trailing: IconButton(
                          tooltip: 'Remove ${profile.label}',
                          onPressed:
                              _service.busy ? null : () => _remove(profile),
                          icon: const Icon(Icons.delete_outline))),
                FilledButton(
                    onPressed:
                        _service.busy || !_service.loaded ? null : _create,
                    child: const Text('Add local profile')),
                TextButton(
                    onPressed: _service.busy ? null : _wipe,
                    child: const Text('Erase all local Neura data')),
              ]),
            ));
      });
}

class _ProfileChat extends StatefulWidget {
  const _ProfileChat({super.key, required this.service, required this.ai});
  final LocalProfileService service;
  final NeuraAiService ai;
  @override
  State<_ProfileChat> createState() => _ProfileChatState();
}

class _ProfileChatState extends State<_ProfileChat> {
  final _input = TextEditingController();
  final List<NeuraChatTurn> _history = [];
  bool _local = true;
  bool _busy = false;
  bool _revoked = false;
  String? _status;
  @override
  void initState() {
    super.initState();
    widget.service.addSessionRevoker(_revoke);
  }

  void _revoke() {
    _revoked = true;
    widget.ai.cancelActiveGeneration();
    _input.clear();
    _history.clear();
    // Remove any open cloud approval or tuning route from this session.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    widget.service.removeSessionRevoker(_revoke);
    widget.ai.cancelActiveGeneration();
    _history.clear();
    _input.dispose();
    super.dispose();
  }

  void _trimHistory() {
    while (_history.length > 8 ||
        _history.fold<int>(0, (n, t) => n + utf8.encode(t.text).length) >
            16384) {
      if (_history.length <= 2) break;
      _history.removeRange(0, 2);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy || !widget.service.canUseSession || _revoked) {
      return;
    }
    final epoch = widget.service.epoch;
    final id = widget.service.active!.id;
    setState(() {
      _busy = true;
      _status = null;
      _input.clear();
      _history.add(NeuraChatTurn(isUser: true, text: text));
      _trimHistory();
    });
    try {
      final request = List<NeuraChatTurn>.of(_history);
      var reply = '';
      setState(
          () => _history.add(const NeuraChatTurn(isUser: false, text: '')));
      await for (final delta in widget.ai.streamReply(request,
          localOllama: _local,
          requestCloudApproval: (preview) => !_revoked &&
                  mounted &&
                  epoch == widget.service.epoch &&
                  id == widget.service.active?.id
              ? showNeuraCloudRequestPreview(context, preview)
              : Future.value(false))) {
        if (!mounted || _revoked || epoch != widget.service.epoch) return;
        if (utf8.encode(reply).length + utf8.encode(delta).length > 12000) {
          widget.ai.cancelActiveGeneration();
          throw StateError('Reply exceeded the visible session budget.');
        }
        reply += delta;
        setState(() {
          _history[_history.length - 1] =
              NeuraChatTurn(isUser: false, text: reply);
        });
      }
      _trimHistory();
    } catch (_) {
      if (mounted && !_revoked) {
        setState(() => _status =
            'Reply unavailable. Check your selected local model or approve a configured cloud request.');
      }
    } finally {
      if (mounted && !_revoked) {
        setState(() {
          _busy = false;
          _trimHistory();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text('Neura · ${widget.service.active?.label ?? ''}'),
            actions: [
              IconButton(
                  tooltip: 'Your Neura',
                  onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PersonaTuningScreen())),
                  icon: const Icon(Icons.tune)),
              IconButton(
                  tooltip: 'End chat and switch profile',
                  onPressed: () => widget.service.lock().catchError((_) {}),
                  icon: const Icon(Icons.switch_account)),
            ]),
        body: SafeArea(
            child: Column(children: [
          SizedBox(
              height: 140,
              child: AvatarView(
                  spec: AvatarRegistry.byId(AvatarRegistry.expressiveFaceId),
                  controller: AvatarGlobals.controller,
                  size: 140)),
          const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                  'Temporary text chat · no shared memories or tools · microphone off')),
          SwitchListTile(
              title: const Text('Use local Ollama'),
              value: _local,
              subtitle: const Text(
                  'Turning this off still requires approval for every configured cloud request.'),
              onChanged:
                  _busy ? null : (value) => setState(() => _local = value)),
          Expanded(
              child: ListView(padding: const EdgeInsets.all(16), children: [
            for (final turn in _history)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child:
                      Text('${turn.isUser ? 'You' : 'Neura'}: ${turn.text}')),
            if (_status != null) Text(_status!),
          ])),
          Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                    child: TextField(
                        controller: _input,
                        inputFormatters: const [
                          NeuraOllamaTextInputFormatter()
                        ],
                        maxLength: 1500,
                        decoration:
                            const InputDecoration(labelText: 'Talk with Neura'),
                        onSubmitted: (_) => _send())),
                IconButton(
                    tooltip: _busy ? 'Stop reply' : 'Send',
                    icon: Icon(_busy ? Icons.stop : Icons.send),
                    onPressed:
                        _busy ? widget.ai.cancelActiveGeneration : _send),
              ])),
        ])),
      );
}
