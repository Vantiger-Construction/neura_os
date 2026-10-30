import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../reliability/safe_boot.dart';
import 'neura_task_transfer.dart';

class NeuraTaskTransferScreen extends StatefulWidget {
  const NeuraTaskTransferScreen({super.key, this.snapshot});
  final NeuraTaskSnapshot? snapshot;
  @override
  State<NeuraTaskTransferScreen> createState() =>
      _NeuraTaskTransferScreenState();
}

class _NeuraTaskTransferScreenState extends State<NeuraTaskTransferScreen>
    with WidgetsBindingObserver {
  final _packet = TextEditingController();
  final _key = TextEditingController();
  NeuraTaskPacket? _sealed;
  NeuraTaskSnapshot? _preview;
  NeuraTaskSnapshot? _source;
  bool _busy = false;
  bool _keyCopied = false;
  String? _status;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _source = widget.snapshot;
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafety);
    SafeBoot.instance.restartRequired.addListener(_onSafety);
  }

  void _onSafety() {
    if (SafeBoot.instance.safeMode.value ||
        SafeBoot.instance.restartRequired.value) {
      _clear();
    }
  }

  void _clear() {
    _epoch++;
    _packet.clear();
    _key.clear();
    _sealed = null;
    _preview = null;
    _source = null;
    _keyCopied = false;
    if (mounted) {
      setState(() =>
          _status = 'Transfer cleared. Return to your plan to start again.');
    }
  }

  bool _current(int epoch) =>
      mounted &&
      epoch == _epoch &&
      !SafeBoot.instance.safeMode.value &&
      !SafeBoot.instance.restartRequired.value;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clear();
  }

  Future<void> _seal() async {
    final source = _source;
    final epoch = _epoch;
    if (_busy || source == null || !_current(epoch)) return;
    setState(() => _busy = true);
    try {
      final result = await NeuraTaskTransfer.seal(source);
      if (_current(epoch)) {
        setState(() {
          _sealed = result;
          _keyCopied = false;
        });
      }
    } catch (_) {
      if (_current(epoch)) {
        setState(() => _status = 'Could not create the transfer.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    final epoch = _epoch;
    if (_busy || !_current(epoch)) return;
    setState(() {
      _busy = true;
      _preview = null;
      _status = null;
    });
    try {
      final result =
          await NeuraTaskTransfer.open(_packet.text.trim(), _key.text.trim());
      if (_current(epoch)) setState(() => _preview = result);
    } catch (_) {
      if (_current(epoch)) {
        setState(() => _status =
            'Could not open the packet. Check the key, expiry and device clocks.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _copy(String text) async {
    final epoch = _epoch;
    if (!_current(epoch)) return false;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!_current(epoch)) return false;
      setState(() => _status =
          'Copied at your request. Your system clipboard may sync between devices.');
      return true;
    } catch (_) {
      if (_current(epoch)) {
        setState(() => _status = 'The clipboard could not be updated.');
      }
      return false;
    }
  }

  Future<void> _savePacket() async {
    final sealed = _sealed;
    if (!_keyCopied || sealed == null || !_current(_epoch)) return;
    // Explicit save may complete in the OS picker after focus changes. Only
    // ciphertext is handed to the picker; plaintext and key are never files.
    try {
      await FilePicker.platform.saveFile(
          fileName: 'neura-task.neuratask',
          type: FileType.custom,
          allowedExtensions: ['neuratask'],
          bytes: Uint8List.fromList(utf8.encode(sealed.packet)));
    } catch (_) {
      if (mounted) setState(() => _status = 'The packet could not be saved.');
    }
  }

  Future<void> _loadPacket() async {
    if (!_current(_epoch) || _busy) return;
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['neuratask'],
          withData: false,
          withReadStream: true);
      if (result == null ||
          !_current(_epoch) ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed &&
              WidgetsBinding.instance.lifecycleState != null) {
        return;
      }
      final epoch = _epoch;
      final file = result.files.single;
      if (file.size > NeuraTaskTransfer.maxPacketCharacters ||
          file.readStream == null) {
        throw const FormatException('Invalid packet file.');
      }
      final bytes = <int>[];
      await for (final chunk in file.readStream!) {
        if (!_current(epoch)) return;
        if (bytes.length + chunk.length >
            NeuraTaskTransfer.maxPacketCharacters) {
          throw const FormatException('Packet too large.');
        }
        bytes.addAll(chunk);
      }
      if (_current(epoch)) {
        setState(() {
          _packet.text = utf8.decode(bytes);
          _preview = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Could not read the encrypted packet.');
      }
    }
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafety);
    SafeBoot.instance.restartRequired.removeListener(_onSafety);
    _packet.dispose();
    _key.dispose();
    _sealed = null;
    _preview = null;
    _source = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Continue on another device')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Transfer one plan manually between Windows and Android. '
            'The packet is encrypted and expires after 30 minutes. '
            'Send the key separately to your own device. Neura sends nothing automatically. '
            'Closing or backgrounding this screen clears its contents; copies you make remain yours to delete.'),
        if (_source case final source?) ...[
          const SizedBox(height: 16),
          Text('Review before exporting',
              style: Theme.of(context).textTheme.titleMedium),
          Text(source.goal),
          for (var i = 0; i < source.steps.length; i++)
            Text(
                '${source.completed.contains(i) ? '✓' : '○'} ${source.steps[i]}'),
          FilledButton(
              onPressed: _busy ? null : _seal,
              child: const Text('Create encrypted task packet')),
        ],
        if (_sealed case final sealed?) ...[
          const Text('Encrypted packet'),
          SelectableText(sealed.packet),
          TextButton(
              onPressed: () => _copy(sealed.packet),
              child: const Text('Copy encrypted packet')),
          const Text('Separate transfer key'),
          SelectableText(sealed.key),
          TextButton(
              onPressed: () async {
                final epoch = _epoch;
                final copied = await _copy(sealed.key);
                if (copied && _current(epoch)) {
                  setState(() => _keyCopied = true);
                }
              },
              child: const Text('Copy transfer key')),
          TextButton(
              onPressed: _keyCopied ? _savePacket : null,
              child: const Text('Save encrypted packet file')),
          const Text(
              'Copy the key first, then save the packet. On the other device, load the packet and paste the key without leaving this screen.'),
        ],
        const Divider(),
        const Text('Receive a task on this device'),
        TextButton(
            onPressed: _busy ? null : _loadPacket,
            child: const Text('Load encrypted packet file')),
        TextField(
            controller: _packet,
            maxLength: NeuraTaskTransfer.maxPacketCharacters,
            maxLines: 3,
            decoration:
                const InputDecoration(labelText: 'Encrypted task packet'),
            onChanged: (_) => setState(() {
                  _epoch++;
                  _preview = null;
                })),
        TextField(
            controller: _key,
            maxLength: 44,
            obscureText: true,
            decoration:
                const InputDecoration(labelText: 'Separate transfer key'),
            onChanged: (_) => setState(() {
                  _epoch++;
                  _preview = null;
                })),
        FilledButton(
            onPressed: _busy ? null : _open,
            child: const Text('Decrypt and preview')),
        if (_preview case final preview?) ...[
          Text(preview.goal, style: Theme.of(context).textTheme.titleLarge),
          for (var i = 0; i < preview.steps.length; i++)
            Text(
                '${preview.completed.contains(i) ? '✓' : '○'} ${preview.steps[i]}'),
          const Text(
              'These are imported claims about progress. Review them before using the plan. No actions or approvals transfer.'),
          FilledButton(
              onPressed: () {
                if (_current(_epoch)) Navigator.pop(context, preview);
              },
              child: const Text('Bring this preview into my planner')),
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_status != null) Text(_status!),
        TextButton(onPressed: _clear, child: const Text('Clear transfer')),
      ]));
}
