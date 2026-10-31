import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../reliability/safe_boot.dart';
import '../services/neura_ai_service.dart';
import '../services/neura_selected_context.dart';
import 'neura_reference_shelf.dart';

class NeuraReferenceShelfScreen extends StatefulWidget {
  const NeuraReferenceShelfScreen({super.key});
  @override
  State<NeuraReferenceShelfScreen> createState() =>
      _NeuraReferenceShelfScreenState();
}

class _NeuraReferenceShelfScreenState extends State<NeuraReferenceShelfScreen>
    with WidgetsBindingObserver {
  final _shelf = NeuraReferenceShelf();
  final _question = TextEditingController();
  List<NeuraReferencePassage> _passages = const [];
  NeuraReferenceGrant? _grant;
  String? _answer;
  String? _status;
  bool _busy = false;
  int _epoch = 0;
  bool get _allowed =>
      mounted &&
      !SafeBoot.instance.safeMode.value &&
      !SafeBoot.instance.restartRequired.value &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  @override
  void initState() {
    super.initState();
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

  void _stop() {
    _epoch++;
    _grant?.revoke();
    _grant = null;
    NeuraAiService.instance.cancelActiveGeneration();
    if (mounted) {
      setState(() {
        _answer = null;
        _busy = false;
      });
    }
  }

  void _clear() {
    _stop();
    _shelf.clear();
    _question.clear();
    if (mounted) {
      setState(() {
        _passages = const [];
        _status = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clear();
  }

  Future<void> _pick() async {
    if (!_allowed || _busy) return;
    _clear();
    try {
      final selected = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: NeuraSelectedContext.extensions,
          withData: false,
          withReadStream: true);
      // Completion of the system picker is the new selection gesture. A focus
      // loss during the picker clears the old source, never authorizes its use.
      if (selected == null ||
          !_allowed ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final epoch = _epoch;
      final file = selected.files.single;
      if (file.size > NeuraSelectedContext.maxBytes ||
          file.readStream == null) {
        throw const FormatException('Choose a text file up to 32 KB.');
      }
      final bytes = <int>[];
      await for (final chunk in file.readStream!) {
        if (!_allowed || epoch != _epoch) return;
        if (bytes.length + chunk.length > NeuraSelectedContext.maxBytes) {
          throw const FormatException('Choose a text file up to 32 KB.');
        }
        bytes.addAll(chunk);
      }
      if (!_allowed || epoch != _epoch) return;
      final document = NeuraSelectedContext.fromBytes(file.name, bytes);
      setState(() {
        _shelf.select(document);
        _status = 'Selected locally. Ask a question to find source passages.';
      });
    } catch (_) {
      if (_allowed) {
        setState(() => _status =
            'Could not read that file. Choose a UTF-8 TXT, MD, CSV or JSON file up to 32 KB.');
      }
    }
  }

  void _find() {
    if (!_allowed || _busy) return;
    setState(() {
      _answer = null;
      _passages = _shelf.find(_question.text.trim());
      _status = _passages.isEmpty
          ? 'No matching passages found. Try a specific word from the document; I cannot establish an answer from this search.'
          : null;
    });
  }

  Future<void> _ask() async {
    if (!_allowed || _busy || _passages.isEmpty) return;
    final epoch = ++_epoch;
    final question = _question.text.trim();
    final grant = _shelf.authorize(question, directUserGesture: true);
    _grant = grant;
    setState(() {
      _busy = true;
      _answer = null;
      _status = null;
    });
    try {
      await for (final text in NeuraAiService.instance.streamReply(
          [NeuraChatTurn(isUser: true, text: question)],
          localOllama: true, offlineReference: grant)) {
        if (!_allowed || epoch != _epoch) return;
        setState(() => _answer = (_answer ?? '') + text);
      }
    } catch (_) {
      if (_allowed && epoch == _epoch) {
        setState(() => _status =
            'Local answer unavailable. The quoted source passages are still available. No cloud request was made.');
      }
    } finally {
      grant.revoke();
      if (identical(_grant, grant)) _grant = null;
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _epoch++;
    _grant?.revoke();
    NeuraAiService.instance.cancelActiveGeneration();
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafety);
    SafeBoot.instance.restartRequired.removeListener(_onSafety);
    _shelf.dispose();
    _question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Offline reference shelf')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'Select one text document. Search shows exact passages with line numbers. '
            'On Windows, approve those passages for one local Ollama excerpt selection. '
            'Replies show complete matching quotations. Check the full source for context and accuracy. '
            'Nothing is saved to memory or sent to the cloud. Leaving the app or entering Safe Mode clears this shelf.'),
        TextButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.description_outlined),
            label: const Text('Select a text document')),
        if (_shelf.name != null) Text('Source: ${_shelf.name}'),
        TextField(
            controller: _question,
            maxLength: 250,
            enabled: !_busy,
            decoration: const InputDecoration(
                labelText: 'Question about this document'),
            onChanged: (_) => setState(() {
                  _epoch++;
                  _passages = const [];
                  _answer = null;
                })),
        FilledButton(
            onPressed: _shelf.name == null || _busy ? null : _find,
            child: const Text('Find source passages')),
        if (_status != null) Text(_status!),
        if (_passages.isNotEmpty)
          const Text('Source preview — exact passages for your approval'),
        for (final p in _passages)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('[${p.number}] ${_shelf.name}, line ${p.line}'),
                        SelectableText(p.text),
                      ]))),
        if (_passages.isNotEmpty &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.windows)
          FilledButton(
              onPressed: _busy ? null : _ask,
              child: const Text('Use these passages for one local answer')),
        if (_busy) ...[
          const LinearProgressIndicator(),
          TextButton(onPressed: _stop, child: const Text('Stop local answer'))
        ],
        if (_answer != null) ...[
          const Text(
              'Local reply — quotations checked against the approved passages'),
          SelectableText(_answer!)
        ],
        TextButton(
            onPressed: _clear,
            child: const Text('Remove document and clear answer')),
      ]));
}
