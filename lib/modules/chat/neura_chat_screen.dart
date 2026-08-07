import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/memory/memory_graph_service.dart';
import '../../neura_shell/neura_shell.dart';
import '../../persona/agents/agent_persona_catalog.dart';
import '../../persona/models/agent_persona.dart';
import '../../persona/services/agent_selection_service.dart';
import '../../services/neura_ai_service.dart';
import '../../services/neura_speech_to_text_service.dart';
import '../../services/neura_tts_service.dart';
import '../../services/wake_word_listener_service.dart';
import '../core/ai_engine.dart';
import '../core/app_log.dart';

class NeuraChatScreen extends StatefulWidget {
  const NeuraChatScreen({super.key});

  @override
  State<NeuraChatScreen> createState() => _NeuraChatScreenState();
}

class _NeuraChatScreenState extends State<NeuraChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatLine> _lines = [
    _ChatLine.bot(
        "Hi. I'm Neura. Tell me what's up — we'll make a plan or we'll breathe first."),
  ];

  bool _speechEnabled = true;
  bool _busy = false;

  final NeuraSpeechToTextService _voiceInput = NeuraSpeechToTextService.instance;
  StreamSubscription<String>? _voiceSub;
  StreamSubscription<String>? _finalPhraseSub;
  bool _listening = false;

  // "Talk freely" mode: once started via the mic, Neura automatically starts
  // listening again after each spoken reply, so the conversation keeps going
  // hands-free instead of needing a fresh tap to start every turn.
  bool _continuousMode = false;

  // Guards against the end-of-turn handler firing twice for one listening
  // session — WinRT's continuous recognizer can in principle deliver more
  // than one 'onFinal' in quick succession (e.g. a multi-sentence turn)
  // while stopRecording() is still in flight for the first one.
  bool _turnEnding = false;

  // Defaults to General synchronously so the first frame has something
  // sensible to show; _initAgent() resolves the real room-based default (or
  // a persisted explicit override) right after.
  AgentPersona _activeAgent = AgentPersonaCatalog.general;

  @override
  void initState() {
    super.initState();
    unawaited(_initAgent());
    // Both this screen's own mic button and the wake-word listener share the
    // one NeuraSpeechToTextService singleton -- pause the listener's
    // reactions while this screen owns the mic to avoid the same phrase
    // being processed by both at once. Resumed on dispose below.
    WakeWordListenerService.instance.pause();
  }

  Future<void> _initAgent() async {
    await AgentSelectionService.instance.load();
    if (!mounted) return;
    final room = NeuraShell.of(context).room;
    setState(() {
      _activeAgent = AgentSelectionService.instance.resolveAgent(room);
    });
  }

  @override
  void dispose() {
    _voiceSub?.cancel();
    _finalPhraseSub?.cancel();
    // _voiceInput is a shared singleton now (other features, e.g. the
    // wake-word listener, may also use it) -- stop listening if this screen
    // left a session running, but never dispose the shared instance.
    if (_listening) {
      unawaited(_voiceInput.stopRecording());
    }
    unawaited(WakeWordListenerService.instance.resume());
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Sentinel distinguishing an explicit "Auto" tap (clears the override)
  // from the sheet being dismissed without a choice (barrier tap, back
  // button) — both of those pop with null, which means "no change".
  static const _autoSentinel = '__auto__';

  Future<void> _openAgentPicker() async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      builder: (sheetContext) {
        final room = NeuraShell.of(context).room;
        final auto = AgentSelectionService.instance.isAuto;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.auto_mode),
                title: const Text('Auto'),
                subtitle: Text('Matches ${room.title}'),
                trailing: auto ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(sheetContext).pop(_autoSentinel),
              ),
              const Divider(height: 1),
              for (final agent in AgentPersonaCatalog.all)
                if (!agent.isInternal)
                  ListTile(
                    leading: Icon(agent.icon),
                    title: Text(agent.displayName),
                    subtitle: Text(agent.tagline),
                    trailing: (!auto && _activeAgent.id == agent.id)
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.of(sheetContext).pop(agent.id),
                  ),
            ],
          ),
        );
      },
    );

    if (selected == null) return; // dismissed without choosing
    await AgentSelectionService.instance.setExplicitAgent(
      selected == _autoSentinel ? null : selected,
    );
    if (!mounted) return;
    final room = NeuraShell.of(context).room;
    setState(() {
      _activeAgent = AgentSelectionService.instance.resolveAgent(room);
    });
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _stopListeningAndSend();
      return;
    }

    _continuousMode = true;
    await _startListeningTurn();
  }

  /// Ends the current listening turn and sends whatever was transcribed.
  /// Called either by the user tapping the mic again, or automatically once
  /// [NeuraSpeechToTextService.finalPhraseStream] reports the user has
  /// finished a thought (WinRT's own pause/endpoint detection) — that's what
  /// makes "talk freely" mode actually hands-free instead of still requiring
  /// a tap to end every turn.
  Future<void> _stopListeningAndSend() async {
    if (_turnEnding) return;
    _turnEnding = true;
    try {
      final text = await _voiceInput.stopRecording();
      if (!mounted) return;
      setState(() {
        _listening = false;
        _controller.text = text;
        _controller.selection =
            TextSelection.collapsed(offset: _controller.text.length);
      });
      // Hands-free loop: turning the mic off sends straight to Neura instead
      // of leaving the transcript sitting in the box for a manual tap.
      unawaited(_send());
    } finally {
      _turnEnding = false;
    }
  }

  Future<void> _startListeningTurn() async {
    if (!_continuousMode || !mounted) return;

    _voiceSub?.cancel();
    _voiceSub = _voiceInput.transcriptStream.listen((partial) {
      if (!mounted) return;
      setState(() {
        _controller.text = partial;
        _controller.selection =
            TextSelection.collapsed(offset: _controller.text.length);
      });
    });

    // In continuous mode, a completed phrase means the user is done talking
    // for this turn — end listening and send automatically rather than
    // waiting for a manual tap on the mic button.
    _finalPhraseSub?.cancel();
    _finalPhraseSub = _voiceInput.finalPhraseStream.listen((_) {
      if (!_continuousMode || !mounted) return;
      unawaited(_stopListeningAndSend());
    });

    final ok = await _voiceInput.startRecording();
    if (!ok) {
      AppLog.instance.info('voice_input_unavailable', {});
      _continuousMode = false;
      return;
    }
    if (!mounted) return;
    setState(() => _listening = true);
  }

  /// Explicit exit for "talk freely" mode — discards anything mid-recording
  /// rather than sending it, since the intent here is "stop", not "send".
  Future<void> _endConversation() async {
    _continuousMode = false;
    unawaited(NeuraTtsService.instance.stop());
    if (_listening) {
      await _voiceInput.stopRecording();
      if (!mounted) return;
      setState(() {
        _listening = false;
        _controller.clear();
      });
    } else {
      setState(() {});
    }
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
    AppLog.instance.info('chat_turn', {'user': text});
    unawaited(_remember(isUser: true, text: text));

    // Skip the hardcoded opening greeting (_lines[0]) — the API requires the
    // conversation to start with a user turn, and that greeting was never
    // actually generated by the model.
    final history = _lines
        .skip(1)
        .where((l) => l.text.isNotEmpty)
        .map((l) => NeuraChatTurn(isUser: l.isUser, text: l.text))
        .toList();

    if (!NeuraAiService.instance.isConfigured) {
      await _fallbackToLocalReply(text);
      return;
    }

    final botLine = _ChatLine.bot('', agentId: _activeAgent.id);
    setState(() => _lines.add(botLine));
    _scrollToEnd();

    try {
      await for (final delta in NeuraAiService.instance
          .streamReply(history, agentId: _activeAgent.id)) {
        setState(() => botLine.text += delta);
        _scrollToEnd();
      }
      unawaited(_remember(isUser: false, text: botLine.text));
      // Awaited (not fire-and-forget): in continuous mode we must not start
      // listening again until Neura is actually done talking, or the mic
      // would pick up her own voice from the speakers.
      if (_speechEnabled) {
        await NeuraTtsService.instance.speak(botLine.text);
      }
    } catch (e) {
      AppLog.instance.info('chat_error', {'error': e.toString()});
      setState(() => _lines.remove(botLine));
      await _fallbackToLocalReply(text);
      return;
    } finally {
      setState(() => _busy = false);
    }

    if (_continuousMode) {
      unawaited(_startListeningTurn());
    }
  }

  Future<void> _fallbackToLocalReply(String text) async {
    final reply = NeuraAICore.instance.respond(text);
    setState(() {
      _lines.add(_ChatLine.bot(reply));
      _busy = false;
    });
    _scrollToEnd();
    unawaited(_remember(isUser: false, text: reply));
    if (_speechEnabled) {
      await NeuraTtsService.instance.speak(reply);
    }
    if (_continuousMode) {
      unawaited(_startListeningTurn());
    }
  }

  /// Persists a real chat turn into the (encrypted, on-device)
  /// [MemoryGraphService] — this is the app's actual conversation history,
  /// as opposed to raw ambient audio, which Neura deliberately does not
  /// record. Fire-and-forget: a memory-write failure must never break the
  /// chat itself.
  Future<void> _remember({required bool isUser, required String text}) async {
    if (text.trim().isEmpty) return;
    try {
      if (isUser) {
        await MemoryGraphService.I.logUserAction(
          kind: 'CHAT_MESSAGE',
          payload: {'text': text},
        );
      } else {
        await MemoryGraphService.I.logSuggestion(
          kind: 'CHAT_REPLY',
          payload: {'text': text},
        );
      }
    } catch (e) {
      await AppLog.instance.warn('chat_memory_log_failed: $e');
    }
  }

  void _toggleSpeech() {
    setState(() => _speechEnabled = !_speechEnabled);
    if (!_speechEnabled) {
      unawaited(NeuraTtsService.instance.stop());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _openAgentPicker,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_activeAgent.icon, size: 20),
              const SizedBox(width: 8),
              Text(_activeAgent.displayName),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 20),
            ],
          ),
        ),
        actions: [
          if (_continuousMode)
            IconButton(
              tooltip: 'End hands-free conversation',
              onPressed: _endConversation,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          IconButton(
            tooltip: _speechEnabled ? 'Mute Neura' : 'Unmute Neura',
            onPressed: _toggleSpeech,
            icon: Icon(_speechEnabled ? Icons.volume_up : Icons.volume_off),
          ),
        ],
      ),
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

                // Only caption a bot line with "who answered" when the agent
                // differs from the previous bot line -- avoids repeating the
                // same label on every turn of an unbroken single-agent run.
                String? agentCaption;
                if (!line.isUser && line.agentId != null) {
                  _ChatLine? prevBotLine;
                  for (var j = i - 1; j >= 0; j--) {
                    if (!_lines[j].isUser) {
                      prevBotLine = _lines[j];
                      break;
                    }
                  }
                  if (prevBotLine?.agentId != line.agentId) {
                    agentCaption =
                        AgentPersonaCatalog.byId(line.agentId!).displayName;
                  }
                }

                return Align(
                  alignment: align,
                  child: Column(
                    crossAxisAlignment: line.isUser
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (agentCaption != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 2),
                          child: Text(
                            agentCaption,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ),
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(maxWidth: 560),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(line.text.isEmpty ? '…' : line.text),
                      ),
                    ],
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
                      decoration: InputDecoration(
                        hintText: _listening
                            ? 'Listening…'
                            : (_continuousMode
                                ? 'Getting ready to listen…'
                                : 'Talk to Neura…'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: _listening
                        ? 'Done — send it'
                        : 'Talk freely (hands-free)',
                    onPressed: _busy ? null : _toggleListening,
                    icon: Icon(
                      _listening ? Icons.mic : Icons.mic_none,
                      color: _listening ? Colors.redAccent : null,
                    ),
                  ),
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
  final String? agentId;
  _ChatLine(this.isUser, this.text, {this.agentId});
  factory _ChatLine.user(String t) => _ChatLine(true, t);
  factory _ChatLine.bot(String t, {String? agentId}) =>
      _ChatLine(false, t, agentId: agentId);
}
