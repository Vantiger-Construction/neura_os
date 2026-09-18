import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../neura_shell/models/neura_room.dart';
import '../neura_shell/neura_shell.dart';
import '../reliability/safe_boot.dart';
import '../services/neura_local_api.dart';
import '../services/neura_tone_runtime.dart';
import '../services/sync_service.dart';

/// A visible review console. Leaving it stops the listener and revokes its token.
class LocalApiScreen extends StatefulWidget {
  const LocalApiScreen({super.key});
  @override
  State<LocalApiScreen> createState() => _LocalApiScreenState();
}

class _LocalApiScreenState extends State<LocalApiScreen>
    with WidgetsBindingObserver {
  late final NeuraLocalApi _api;
  Timer? _expiryTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = NeuraLocalApi(
      allowed: () => mounted && !SafeBoot.instance.safeMode.value,
      onChanged: () {
        if (mounted && !_disposing) setState(() {});
      },
    );
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_safeModeChanged);
    _expiryTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  void _safeModeChanged() {
    if (SafeBoot.instance.safeMode.value) unawaited(_api.stop());
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_api.stop());
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_safeModeChanged);
    // Suppress callbacks during disposal before closing native sockets.
    _disposing = true;
    unawaited(_api.stop());
    super.dispose();
  }

  bool _disposing = false;

  Future<void> _toggle() async {
    try {
      if (_api.running) {
        await _api.stop();
      } else {
        await _api.start();
      }
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = 'The local API could not start.');
    }
  }

  Future<void> _review(String id) async {
    final proposal = _api.takeForApproval(id);
    if (proposal == null) return;
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Approve this local app request?'),
              content: Text(
                  '${proposal.action}\n${jsonEncode(proposal.arguments)}\n\n${proposal.action == 'sync_journal' ? 'This sends and retrieves journal entries through your configured cloud account.' : 'This changes Neura on this device.'}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Deny')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Approve once')),
              ],
            ));
    if (!mounted || approved != true || !_api.canApply(proposal)) {
      _api.finish(proposal, 'denied');
      return;
    }
    try {
      switch (proposal.action) {
        case 'open_room':
          await NeuraShell.of(context)
              .setRoom(NeuraRoom.fromId(proposal.arguments['room'] as String));
          break;
        case 'set_tone':
          if (!NeuraToneRuntime.instance
              .setTone(proposal.arguments['tone'] as String)) {
            throw StateError('Tone unavailable');
          }
          break;
        case 'sync_journal':
          final result = await SyncService().syncAll();
          _api.finish(proposal, result.succeeded ? 'finished' : 'retry_needed');
          return;
      }
      _api.finish(proposal, 'finished');
    } catch (_) {
      _api.finish(proposal, 'failed');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Local app API')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text(
              'Connect a trusted app on this device. Each action appears here for your approval. No journal, memory, microphone or AI access is exposed.'),
          const SizedBox(height: 12),
          const Text(
              'Off by default. Closing this screen, backgrounding Neura or entering Safe Mode stops the API and revokes its session token.'),
          SwitchListTile(
              title: const Text('Allow local app proposals'),
              value: _api.running,
              onChanged:
                  SafeBoot.instance.safeMode.value ? null : (_) => _toggle()),
          if (_error != null) Text(_error!),
          if (_api.running) ...[
            SelectableText('http://127.0.0.1:${_api.port}/v1'),
            const SizedBox(height: 12),
            ExpansionTile(
                title: const Text('Show token for a trusted local app'),
                children: [SelectableText(_api.token!)]),
            const Text(
                'Use Authorization: Bearer <token>. Keep this token private.'),
          ],
          const SizedBox(height: 20),
          const Text('Requests awaiting review (expire after two minutes)'),
          for (final proposal in _api.pending)
            Card(
                child: ListTile(
                    title: Text(proposal.action),
                    subtitle: Text(jsonEncode(proposal.arguments)),
                    trailing: TextButton(
                        onPressed: () => _review(proposal.id),
                        child: const Text('Review')))),
        ]),
      );
}
