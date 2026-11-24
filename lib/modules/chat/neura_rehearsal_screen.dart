import 'dart:async';

import 'package:flutter/material.dart';

import '../../relationships/services/crisis_text_scan.dart';
import '../../services/neura_ai_service.dart';
import '../../services/neura_rehearsal.dart';
import '../../widgets/neura_cloud_request_preview.dart';

/// Practise a hard conversation: Neura plays the other person, then steps
/// out of the role with gentle feedback. Nothing here is saved; closing the
/// screen forgets the practice.
class NeuraRehearsalScreen extends StatefulWidget {
  const NeuraRehearsalScreen({
    super.key,
    required this.localOllama,
    this.aiService,
  });

  /// Practise on this computer (Ollama) instead of the cloud provider.
  final bool localOllama;
  final NeuraAiService? aiService;

  @override
  State<NeuraRehearsalScreen> createState() => _NeuraRehearsalScreenState();
}

class _NeuraRehearsalScreenState extends State<NeuraRehearsalScreen> {
  final _who = TextEditingController();
  final _goal = TextEditingController();
  final _message = TextEditingController();
  final _scroll = ScrollController();
  var _reaction = NeuraRehearsalReaction.guarded;
  NeuraRehearsal? _rehearsal;
  final _lines = <NeuraRehearsalLine>[];
  String? _feedback;
  bool _busy = false;
  bool _stopped = false;

  NeuraAiService get _ai => widget.aiService ?? NeuraAiService.instance;

  @override
  void dispose() {
    _who.dispose();
    _goal.dispose();
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int get _userTurns => _lines.where((line) => line.fromUser).length;

  void _start() {
    try {
      setState(() {
        _rehearsal = NeuraRehearsal(
          who: _who.text,
          goal: _goal.text,
          reaction: _reaction,
        );
      });
    } on ArgumentError catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${error.message}')));
    }
  }

  Future<NeuraRehearsalTurn?> _turn(
    String system,
    List<Map<String, String>> messages,
  ) async {
    try {
      return await _ai.rehearsalTurn(
        system: system,
        messages: messages,
        localOllama: widget.localOllama,
        requestCloudApproval: (preview) => mounted
            ? showNeuraCloudRequestPreview(context, preview)
            : Future.value(false),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.localOllama
              ? 'Offline practice is unavailable. Check that Ollama is open.'
              : 'Practice reply unavailable: $error'),
        ));
      }
      return null;
    }
  }

  Future<void> _say() async {
    final rehearsal = _rehearsal;
    final text = _message.text.trim();
    if (rehearsal == null || text.isEmpty || _busy || _stopped) return;
    setState(() {
      _lines.add(NeuraRehearsalLine(fromUser: true, text: text));
      _message.clear();
      _busy = true;
    });
    _scrollToEnd();
    // Real distress is not something to rehearse past.
    if (CrisisTextScan.of(text).crisis) {
      setState(() => _stopped = true);
    }
    final turn = await _turn(
      rehearsal.characterPrompt,
      rehearsal.characterMessages(_lines),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (turn == null) return;
      _lines.add(NeuraRehearsalLine(fromUser: false, text: turn.text));
      if (turn.blocked) _stopped = true;
    });
    _scrollToEnd();
  }

  Future<void> _finish() async {
    final rehearsal = _rehearsal;
    if (rehearsal == null || _busy || _userTurns == 0) return;
    setState(() => _busy = true);
    final turn = await _turn(
      'You are Neura, a warm and encouraging companion.',
      [
        {'role': 'user', 'content': rehearsal.feedbackPrompt(_lines)},
      ],
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (turn != null) {
        _feedback = turn.text;
        _stopped = true;
      }
    });
    _scrollToEnd();
  }

  void _restart() => setState(() {
        _lines.clear();
        _feedback = null;
        _stopped = false;
      });

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rehearsal = _rehearsal;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rehearse a hard talk'),
        actions: [
          if (rehearsal != null)
            TextButton(
              onPressed: _busy || _userTurns == 0 || _feedback != null
                  ? null
                  : _finish,
              child: const Text('How did I do?'),
            ),
        ],
      ),
      body: SafeArea(
        child: rehearsal == null ? _setup(context) : _practice(rehearsal),
      ),
    );
  }

  Widget _setup(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            "Practise what you want to say. I'll play the other person, then "
            'tell you what went well. Nothing here is saved.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('rehearsal-who'),
            controller: _who,
            maxLength: NeuraRehearsal.maxWhoLength,
            decoration: const InputDecoration(
              labelText: 'Who is the talk with?',
              hintText: 'My manager, my brother, my landlord…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('rehearsal-goal'),
            controller: _goal,
            maxLength: NeuraRehearsal.maxGoalLength,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'What do you want to say or ask?',
              hintText: 'I need to ask for a day off for my mental health.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text('How might they react?',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<NeuraRehearsalReaction>(
            segments: [
              for (final reaction in NeuraRehearsalReaction.values)
                ButtonSegment(value: reaction, label: Text(reaction.label)),
            ],
            selected: {_reaction},
            onSelectionChanged: (value) =>
                setState(() => _reaction = value.single),
          ),
          const SizedBox(height: 8),
          Text(
            widget.localOllama
                ? 'Runs on this computer with Ollama.'
                : 'Uses your cloud provider; each request asks first.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('rehearsal-start'),
            onPressed: _start,
            icon: const Icon(Icons.record_voice_over_outlined),
            label: const Text('Start practising'),
          ),
        ],
      );

  Widget _practice(NeuraRehearsal rehearsal) {
    final theme = Theme.of(context);
    final atLimit = _userTurns >= NeuraRehearsal.maxTurns;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Practising with ${rehearsal.who}. Start whenever you are ready.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            children: [
              for (final line in _lines)
                Align(
                  alignment: line.fromUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 520),
                    decoration: BoxDecoration(
                      color: line.fromUser
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.fromUser ? 'You' : rehearsal.who,
                          style: theme.textTheme.labelSmall,
                        ),
                        const SizedBox(height: 2),
                        SelectableText(line.text),
                      ],
                    ),
                  ),
                ),
              if (_busy) const LinearProgressIndicator(),
              if (_feedback != null)
                Card(
                  margin: const EdgeInsets.only(top: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('From Neura', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        SelectableText(_feedback!),
                      ],
                    ),
                  ),
                ),
              if (_stopped)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(spacing: 8, children: [
                    OutlinedButton(
                      onPressed: _busy ? null : _restart,
                      child: const Text('Practise again'),
                    ),
                    OutlinedButton(
                      onPressed: () => setState(() => _rehearsal = null),
                      child: const Text('Change the setup'),
                    ),
                  ]),
                ),
            ],
          ),
        ),
        if (!_stopped)
          Padding(
            padding: const EdgeInsets.all(12),
            child: atLimit
                ? FilledButton(
                    onPressed: _busy ? null : _finish,
                    child:
                        const Text('That was a good practice. How did I do?'),
                  )
                : Row(children: [
                    Expanded(
                      child: TextField(
                        key: const Key('rehearsal-message'),
                        controller: _message,
                        enabled: !_busy,
                        onSubmitted: (_) => _say(),
                        decoration: InputDecoration(
                          hintText: 'Say it to ${rehearsal.who}…',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _busy ? null : _say,
                      icon: const Icon(Icons.send),
                      tooltip: 'Send',
                    ),
                  ]),
          ),
      ],
    );
  }
}
