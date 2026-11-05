import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../reliability/safe_boot.dart';
import '../../services/portable_vault_backup_service.dart';

/// Local verification and an explicit, revocable selection before vault writes.
class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen(
      {super.key, required this.service, required this.sessionPin});
  final PortableVaultBackupService service;
  final String? Function() sessionPin;

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen>
    with WidgetsBindingObserver {
  final _passphrase = TextEditingController();
  String? _envelope;
  String? _fileName;
  String? _status;
  PortableBackupPreview? _preview;
  final _selected = <int>{};
  Object? _operation;
  Object? _pickerRequest;
  Completer<void>? _resumed;
  bool _awaitingPicker = false;
  bool _restored = false;
  bool _writing = false;
  bool _confirming = false;
  int _epoch = 0;

  bool get _safe =>
      !SafeBoot.instance.safeMode.value &&
      !SafeBoot.instance.restartRequired.value;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _allowed =>
      mounted && _safe && _foreground && widget.sessionPin() != null;
  bool get _busy => _operation != null || _writing;
  bool _current(int epoch, Object operation) =>
      _allowed && epoch == _epoch && identical(_operation, operation);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafety);
    SafeBoot.instance.restartRequired.addListener(_onSafety);
  }

  void _onSafety() {
    if (!_safe) _clear();
  }

  void _invalidatePicker() {
    _pickerRequest = null;
    _awaitingPicker = false;
    _resumed?.complete();
    _resumed = null;
  }

  void _clear({bool preservePicker = false}) {
    _epoch++;
    _preview?.revoke();
    _preview = null;
    _selected.clear();
    _passphrase.clear();
    _envelope = null;
    _fileName = null;
    _status = null;
    if (!preservePicker) {
      _invalidatePicker();
      _operation = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _awaitingPicker = false;
      _resumed?.complete();
      _resumed = null;
    } else {
      _clear(
          preservePicker:
              _awaitingPicker && state != AppLifecycleState.detached);
    }
  }

  Future<void> _pick() async {
    if (!_allowed || _busy) return;
    _clear();
    final request = Object();
    _pickerRequest = request;
    _operation = request;
    _awaitingPicker = true;
    setState(() {});
    bool ownsRequest() =>
        mounted &&
        _safe &&
        identical(_pickerRequest, request) &&
        identical(_operation, request);
    try {
      final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const ['neurabackup'],
          dialogTitle: 'Choose encrypted backup');
      if (file == null || !ownsRequest()) return;
      if (!_foreground) {
        final resumed = Completer<void>();
        _resumed = resumed;
        await resumed.future;
      }
      if (!ownsRequest() ||
          !_allowed ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _awaitingPicker = false;
      final epoch = _epoch;
      final envelope = await widget.service
          .readBackupFile(file, mayRead: () => _current(epoch, request));
      if (!_current(epoch, request)) return;
      setState(() {
        _envelope = envelope;
        _fileName = file.name;
      });
    } catch (_) {
      if (ownsRequest() && _allowed) {
        setState(() => _status =
            'Could not read that backup. Choose a .neurabackup file up to 25 MB.');
      }
    } finally {
      if (identical(_pickerRequest, request)) _invalidatePicker();
      if (mounted && identical(_operation, request)) {
        setState(() => _operation = null);
      }
    }
  }

  Future<void> _verify() async {
    if (!_allowed || _busy || _envelope == null) return;
    final operation = Object();
    final epoch = _epoch;
    final envelope = _envelope!;
    final passphrase = _passphrase.text;
    _passphrase.clear();
    _preview?.revoke();
    _preview = null;
    _selected.clear();
    setState(() {
      _operation = operation;
      _status = null;
    });
    try {
      final preview =
          await widget.service.previewRestore(envelope, passphrase: passphrase);
      if (!_current(epoch, operation)) {
        preview.revoke();
        return;
      }
      setState(() {
        _preview = preview;
        _envelope = null;
        _status =
            'Verified ${preview.items.length} entries. Your vault has not changed.';
      });
    } catch (_) {
      if (_current(epoch, operation)) {
        setState(() => _status =
            'Backup verification failed. Check the file and passphrase. Your vault has not changed.');
      }
    } finally {
      if (mounted && identical(_operation, operation)) {
        setState(() => _operation = null);
      }
    }
  }

  Future<void> _restore() async {
    final preview = _preview;
    final pin = widget.sessionPin();
    if (!_allowed ||
        _busy ||
        preview == null ||
        !preview.isCurrent ||
        pin == null ||
        _selected.isEmpty) {
      return;
    }
    final epoch = _epoch;
    final operation = Object();
    final selection = Set<int>.of(_selected);
    setState(() {
      _operation = operation;
      _confirming = true;
    });
    try {
      final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text('Restore ${selection.length} selected entries?'),
                content: const Text(
                    'Only these entries will be added. Identical entries are skipped; conflicting versions are kept as separate entries.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Restore selected')),
                ],
              ));
      _confirming = false;
      if (confirm != true ||
          !_current(epoch, operation) ||
          !preview.isCurrent ||
          widget.sessionPin() != pin) {
        return;
      }
      setState(() {
        _writing = true;
        _preview = null;
        _selected.clear();
      });
      final count = await widget.service
          .restorePreview(pin: pin, preview: preview, selected: selection);
      if (!_current(epoch, operation)) return;
      setState(() {
        _restored = true;
        _preview = null;
        _selected.clear();
        _status =
            'Restored $count ${count == 1 ? 'entry' : 'entries'}. Existing entries were preserved.';
      });
    } catch (_) {
      if (_current(epoch, operation)) {
        preview.revoke();
        setState(() {
          _preview = null;
          _selected.clear();
          _status =
              'Restore could not be confirmed. Check your vault before trying again.';
        });
      }
    } finally {
      _writing = false;
      _confirming = false;
      if (mounted) {
        setState(() {
          if (identical(_operation, operation)) _operation = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _epoch++;
    _operation = null;
    _invalidatePicker();
    _preview?.revoke();
    _preview = null;
    _envelope = null;
    _passphrase.dispose();
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafety);
    SafeBoot.instance.restartRequired.removeListener(_onSafety);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify and restore backup')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'Check an encrypted backup locally without changing your vault. Then choose which entries to restore. Verification and selections clear when you leave the app or enter Safe Mode.'),
        TextButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose encrypted backup')),
        if (_fileName != null) Text('Selected: $_fileName'),
        if (_envelope != null) ...[
          TextField(
              controller: _passphrase,
              enabled: !_busy,
              obscureText: true,
              maxLength: 256,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Backup passphrase'),
              onSubmitted: (_) {
                if (!_busy) unawaited(_verify());
              }),
          FilledButton(
              onPressed: _busy ? null : _verify,
              child: const Text('Verify without importing')),
        ],
        if (_busy && !_confirming) const LinearProgressIndicator(),
        if (_status != null) Semantics(liveRegion: true, child: Text(_status!)),
        if (preview != null &&
            preview.isCurrent &&
            preview.items.isNotEmpty) ...[
          const Text(
              'Choose entries to restore. None are selected automatically.'),
          Text('${_selected.length} selected'),
          Wrap(spacing: 8, children: [
            TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _selected
                        .addAll(List.generate(preview.items.length, (i) => i))),
                child: const Text('Select all')),
            TextButton(
                onPressed: _busy ? null : () => setState(_selected.clear),
                child: const Text('Select none')),
          ]),
          SizedBox(
              height: 300,
              child: ListView.builder(
                  itemCount: preview.items.length,
                  itemBuilder: (context, index) {
                    final item = preview.items[index];
                    return CheckboxListTile(
                        title: Text(
                            item.title.isEmpty ? 'Untitled entry' : item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(MaterialLocalizations.of(context)
                            .formatMediumDate(item.createdAt)),
                        value: _selected.contains(index),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  if (value == true) {
                                    _selected.add(index);
                                  } else {
                                    _selected.remove(index);
                                  }
                                }));
                  })),
          FilledButton(
              onPressed: _busy || _selected.isEmpty ? null : _restore,
              child: const Text('Review selected restore')),
        ],
        TextButton(onPressed: _clear, child: const Text('Clear backup review')),
        TextButton(
            onPressed: () => Navigator.pop(context, _restored),
            child: const Text('Back to vault')),
      ]),
    );
  }
}
