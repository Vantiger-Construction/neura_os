import 'dart:async';

import 'package:flutter/material.dart';

import '../../persona/agents/agent_persona_catalog.dart';
import '../../persona/models/neura_audience.dart';
import '../../persona/services/neura_audience_service.dart';
import '../../services/neura_ai_service.dart';
import '../../services/neura_tts_service.dart';

/// Real Neura chat for Kids Mode. Replaces the old stub (which only ever
/// displayed the system prompt it built, never called an LLM).
///
/// Safety note: [NeuraPromptBuilder.buildSystemMessage]'s `audience`
/// parameter is currently unused internally -- the actual kid-safety gate is
/// [Guardrails], which reads the *global, persisted* [NeuraAudienceService]
/// setting (see NeuraAiService._checkGuardrails). Kids Mode itself never set
/// that global toggle, so without this, a child using this screen would run
/// under whatever audience the adult had last chosen in Settings. This
/// screen now force-sets it to `child` for as long as it's open and restores
/// the previous value on exit, so guardrails are actually correct while a
/// child could plausibly be typing.
///
/// Privacy note: unlike the adult chat screen, turns here are deliberately
/// NOT written to [MemoryGraphService] -- a child's conversation shouldn't
/// silently feed the same long-term memory/profile summary built from the
/// adult's own chats.
class KidsNeuraChatScreen extends StatefulWidget {
  const KidsNeuraChatScreen({super.key});

  @override
  State<KidsNeuraChatScreen> createState() => _KidsNeuraChatScreenState();
}

class _KidsNeuraChatScreenState extends State<KidsNeuraChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatLine> _lines = [
    _ChatLine.bot("Hi! I'm Neura. What do you want to talk about?"),
  ];

  bool _busy = false;
  NeuraAudience? _previousAudience;

  @override
  void initState() {
    super.initState();
    unawaited(_forceChildAudience());
  }

  Future<void> _forceChildAudience() async {
    await NeuraAudienceService.instance.load();
    _previousAudience = NeuraAudienceService.instance.currentAudience;
    await NeuraAudienceService.instance.setAudience(NeuraAudience.child);
  }

  @override
  void dispose() {
    final previous = _previousAudience;
    if (previous != null) {
      unawaited(NeuraAudienceService.instance.setAudience(previous));
    }
    unawaited(NeuraTtsService.instance.stop());
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;

    setState(() {
      _lines.add(_ChatLine.user(text));
      _controller.clear();
      _busy = true;
    });
    _scrollToEnd();

    final history = _lines
        .skip(1)
        .where((l) => l.text.isNotEmpty)
        .map((l) => NeuraChatTurn(isUser: l.isUser, text: l.text))
        .toList();

    if (!NeuraAiService.instance.isConfigured) {
      setState(() {
        _lines.add(_ChatLine.bot(
            "I can't chat for real right now -- ask a grown-up to check the app setup."));
        _busy = false;
      });
      _scrollToEnd();
      return;
    }

    final botLine = _ChatLine.bot('');
    setState(() => _lines.add(botLine));
    _scrollToEnd();

    try {
      await for (final delta in NeuraAiService.instance.streamReply(
        history,
        agentId: AgentPersonaCatalog.generalId,
      )) {
        setState(() => botLine.text += delta);
        _scrollToEnd();
      }
      await NeuraTtsService.instance.speak(botLine.text);
    } catch (_) {
      setState(() {
        _lines.remove(botLine);
        _lines.add(_ChatLine.bot(
            "Hmm, I couldn't think of a reply just then. Try again?"));
      });
      _scrollToEnd();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Talk to Neura')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _lines.length,
              itemBuilder: (context, i) {
                final line = _lines[i];
                final align =
                    line.isUser ? Alignment.centerRight : Alignment.centerLeft;
                final color = line.isUser
                    ? Colors.blueGrey.shade700
                    : Colors.grey.shade900;
                return Align(
                  alignment: align,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 560),
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(14)),
                    child: Text(line.text.isEmpty ? '…' : line.text),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_busy,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Type something...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _busy ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatLine {
  final bool isUser;
  String text;
  _ChatLine(this.isUser, this.text);
  factory _ChatLine.user(String t) => _ChatLine(true, t);
  factory _ChatLine.bot(String t) => _ChatLine(false, t);
}
