import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/memory/memory_graph_service.dart';
import '../../modules/mood/mood_models.dart';
import '../../modules/mood/mood_store.dart';
import '../../neura_shell/models/neura_room.dart';
import '../../neura_shell/neura_shell.dart';
import '../../persona/agents/agent_persona_catalog.dart';
import '../../persona/models/agent_persona.dart';
import '../../persona/services/agent_selection_service.dart';
import '../../services/neura_ai_service.dart';
import '../../services/neura_chat_policy.dart';
import '../../services/neura_generation_cancel.dart';
import '../../services/neura_llm_diagnostics.dart';
import '../../services/neura_speech_to_text_service.dart';
import '../../services/neura_swarm_service.dart';
import '../../services/neura_tone_runtime.dart';
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
  String? _activeReplyId;
  _ChatLine? _activeBotLine;
  int _generationSerial = 0;

  final NeuraSpeechToTextService _voiceInput = NeuraSpeechToTextService.instance;
  final ImagePicker _imagePicker = ImagePicker();
  StreamSubscription<String>? _voiceSub;
  StreamSubscription<String>? _finalPhraseSub;
  bool _listening = false;

  // "Talk freely" mode: once started via the mic, Neura automatically starts
  // listening again after each spoken reply, so the conversation keeps going
  // hands-free instead of needing a fresh tap to start every turn.
  bool _continuousMode = false;

  // Guards against the end-of-turn handler firing twice for one listening
  // session — WinRT's continuous recognizer can in principle deliver more
  // than one 'onFinal' in quick succession while stopRecording() is in flight.
  bool _turnEnding = false;

  AgentPersona _activeAgent = AgentPersonaCatalog.general;

  @override
  void initState() {
    super.initState();
    unawaited(_initAgent());
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
    NeuraAiService.instance.cancelActiveGeneration();
    unawaited(NeuraTtsService.instance.stop());
    if (_listening) {
      unawaited(_voiceInput.stopRecording());
    }
    unawaited(WakeWordListenerService.instance.resume());
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

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

    if (selected == null) return;
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
      unawaited(_send());
    } finally {
      _turnEnding = false;
    }
  }

  Future<void> _startListeningTurn() async {
    if (!_continuousMode || !mounted) return;

    unawaited(_voiceSub?.cancel());
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
    unawaited(_finalPhraseSub?.cancel());
    _finalPhraseSub = _voiceInput.finalPhraseStream.listen((_) {
      if (!_continuousMode || !mounted) return;
      unawaited(_stopListeningAndSend());
    });

    final ok = await _voiceInput.startRecording();
    if (!ok) {
      await AppLog.instance.info('voice_input_unavailable', {});
      _continuousMode = false;
      return;
    }
    if (!mounted) return;
    setState(() => _listening = true);
  }

  Future<void> _endConversation() async {
    _continuousMode = false;
    await _interruptActiveReply();
    if (_listening) {
      await _voiceInput.stopRecording();
      if (!mounted) return;
      setState(() {
        _listening = false;
        _controller.clear();
      });
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _beginVoiceBargeIn() async {
    if (_busy) await _interruptActiveReply();
    if (!mounted) return;
    await _toggleListening();
  }

  /// Stops both the in-flight model stream and TTS. The partial/full bot line
  /// remains visible and is marked interrupted so correlation with its
  /// generation id is preserved instead of silently deleting output.
  Future<void> _interruptActiveReply() async {
    final interruptedId = _activeReplyId;
    final interruptedLine = _activeBotLine;
    NeuraAiService.instance.cancelActiveGeneration();
    await NeuraTtsService.instance.stop();

    if (interruptedId != null) {
      await AppLog.instance.info('speak_interrupted', {
        'utterance_id': interruptedId,
        'seq': interruptedLine?.seq ?? 0,
      });
    }

    if (!mounted) return;
    setState(() {
      if (interruptedLine != null) interruptedLine.interrupted = true;
      _activeReplyId = null;
      _activeBotLine = null;
      _busy = false;
    });
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

  Future<void> _pickAndSendImage() async {
    if (_busy) return;
    final XFile? picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1568,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').last.toLowerCase();
    final mediaType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
    await _send(imageBase64: base64Encode(bytes), imageMediaType: mediaType);
  }

  Future<void> _send({String? imageBase64, String? imageMediaType}) async {
    final text = _controller.text.trim();
    final hasImage = imageBase64 != null;
    if (text.isEmpty && !hasImage) return;

    if (_busy) {
      await _interruptActiveReply();
      if (!mounted) return;
    }

    final room = NeuraShell.of(context).room;
    final policy = NeuraChatPolicy.forRoom(room.id);
    final displayText =
        text.isEmpty && hasImage ? 'What do you see in this photo?' : text;
    final generationId =
        '${DateTime.now().microsecondsSinceEpoch}-${_generationSerial++}';

    setState(() {
      _lines.add(_ChatLine.user(
        displayText,
        utteranceId: generationId,
        imageBase64: imageBase64,
        imageMediaType: imageMediaType,
      ));
      _controller.clear();
      _busy = true;
      _activeReplyId = generationId;
    });
    _scrollToEnd();
    await AppLog.instance.info('chat_turn', {
      'character_count': displayText.runes.length,
      'has_image': hasImage,
      'utterance_id': generationId,
      'room': room.id,
      'persist': policy.persistMemory,
    });
    unawaited(_remember(
      isUser: true,
      text: displayText,
      persistMemory: policy.persistMemory,
    ));

    final history = _lines
        .skip(1)
        .where((l) => l.text.isNotEmpty || l.imageBase64 != null)
        .map((l) => NeuraChatTurn(
              isUser: l.isUser,
              text: l.text,
              imageBase64: l.imageBase64,
              imageMediaType: l.imageMediaType,
            ))
        .toList();

    if (!NeuraAiService.instance.isConfigured) {
      await _fallbackToLocalReply(
        displayText,
        generationId: generationId,
        persistMemory: policy.persistMemory,
      );
      return;
    }

    final botLine = _ChatLine.bot(
      '',
      agentId: _activeAgent.id,
      utteranceId: generationId,
    );
    setState(() {
      _lines.add(botLine);
      _activeBotLine = botLine;
    });
    _scrollToEnd();

    try {
      await for (final delta in NeuraAiService.instance.streamReply(
        history,
        agentId: _activeAgent.id,
        roomId: room.id,
        generationId: generationId,
        onToolCommand: _handleToolCommand,
      )) {
        if (!mounted || _activeReplyId != generationId) return;
        setState(() {
          botLine.text += delta;
          botLine.seq += 1;
        });
        _scrollToEnd();
      }

      if (!mounted || _activeReplyId != generationId) return;
      await AppLog.instance.info('chat_reply_complete', {
        'utterance_id': generationId,
        'seq': botLine.seq,
        'room': room.id,
      });
      unawaited(_remember(
        isUser: false,
        text: botLine.text,
        persistMemory: policy.persistMemory,
      ));
      unawaited(_runSwarm(
        userMessage: displayText,
        draftReply: botLine.text,
        history: history,
        persistMemory: policy.persistMemory,
      ));

      if (_speechEnabled && botLine.text.trim().isNotEmpty) {
        await NeuraTtsService.instance.speak(botLine.text);
      }
    } on NeuraGenerationCancelled catch (e) {
      await AppLog.instance.info('chat_generation_cancelled', {
        'utterance_id': e.generationId,
        'seq': botLine.seq,
      });
      if (mounted) {
        setState(() => botLine.interrupted = true);
      }
      return;
    } catch (error, stack) {
      await AppLog.instance.caught(
        'chat_generation_failed',
        error,
        stack,
        context: <String, Object?>{'utterance_id': generationId},
      );
      if (!mounted || _activeReplyId != generationId) return;

      if (botLine.text.isEmpty) {
        setState(() => _lines.remove(botLine));
        await _fallbackToLocalReply(
          displayText,
          generationId: generationId,
          persistMemory: policy.persistMemory,
        );
      } else {
        setState(() => botLine.interrupted = true);
      }
      return;
    } finally {
      if (mounted && _activeReplyId == generationId) {
        setState(() {
          _busy = false;
          _activeReplyId = null;
          _activeBotLine = null;
        });
      }
    }

    if (_continuousMode && mounted && !_busy) {
      unawaited(_startListeningTurn());
    }
  }

  Future<void> _fallbackToLocalReply(
    String text, {
    required String generationId,
    required bool persistMemory,
  }) async {
    NeuraLlmDiagnostics.instance.recordFallback();
    final reply = NeuraAICore.instance.respond(text);
    if (!mounted || _activeReplyId != generationId) return;

    final fallbackLine = _ChatLine.bot(
      reply,
      agentId: _activeAgent.id,
      utteranceId: generationId,
    );
    setState(() {
      _lines.add(fallbackLine);
      _activeBotLine = fallbackLine;
    });
    _scrollToEnd();
    unawaited(_remember(
      isUser: false,
      text: reply,
      persistMemory: persistMemory,
    ));
    if (_speechEnabled) {
      await NeuraTtsService.instance.speak(reply);
    }

    if (!mounted || _activeReplyId != generationId) return;
    setState(() {
      _busy = false;
      _activeReplyId = null;
      _activeBotLine = null;
    });
    if (_continuousMode) {
      unawaited(_startListeningTurn());
    }
  }

  /// Long-term memory writes are skipped entirely in ephemeral room policy.
  /// The visible conversation still remains in [_lines] for working memory.
  Future<void> _remember({
    required bool isUser,
    required String text,
    required bool persistMemory,
  }) async {
    if (!persistMemory || text.trim().isEmpty) return;
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
    } catch (e, st) {
      await AppLog.instance.caught('chat_memory_log_failed', e, st);
    }
  }

  Future<void> _runSwarm({
    required String userMessage,
    required String draftReply,
    required List<NeuraChatTurn> history,
    required bool persistMemory,
  }) async {
    try {
      final outcome = await NeuraSwarmService.instance.reviewAndExtract(
        transcript: _transcriptSnippet(history),
        draftReply: draftReply,
        userMessage: userMessage,
      );

      if (outcome.concernNote != null && mounted) {
        setState(() => _lines.add(
              _ChatLine.bot(outcome.concernNote!, agentId: _activeAgent.id),
            ));
        _scrollToEnd();
      }

      // The critic may still run in an ephemeral room, but extracted facts
      // never cross the persistence gate.
      if (!persistMemory) return;
      for (final fact in outcome.facts) {
        await MemoryGraphService.I.logUserAction(
          kind: 'SWARM_MEMORY_FACT',
          payload: {'summary': fact.summary, 'factKind': fact.kind},
        );
      }
    } catch (e, st) {
      await AppLog.instance.caught('chat_swarm_failed', e, st);
    }
  }

  Future<bool> _handleToolCommand(NeuraToolCommand command) async {
    if (!mounted) return false;
    switch (command.name) {
      case NeuraChatPolicy.getMoodHistory:
        return _confirmToolAction(
          title: 'Share mood scores once?',
          message: 'Neura wants to send recent mood dates and 0–10 scores to '
              'the configured AI provider for this reply. Your mood notes '
              'will not be shared.',
          approveLabel: 'Share once',
        );
      case NeuraChatPolicy.logMoodEntry:
        final mood = (command.arguments['mood0to10'] as num?)
            ?.round()
            .clamp(0, 10)
            .toInt();
        if (mood == null) return false;
        final note = command.arguments['note']?.toString() ?? '';
        final approved = await _confirmToolAction(
          title: 'Save this mood check-in?',
          message: note.trim().isEmpty
              ? 'Save mood $mood/10 to your encrypted local history?'
              : 'Save mood $mood/10 with the note “$note” to your encrypted '
                  'local history?',
          approveLabel: 'Save locally',
        );
        if (!approved) return false;
        await MoodStore.instance.add(
          MoodEntry(
            timestamp: DateTime.now(),
            mood0to10: mood,
            note: note,
          ),
        );
        return true;
      case NeuraChatPolicy.dispatchIntent:
        final roomId = command.arguments['room']?.toString() ?? '';
        if (!NeuraChatPolicy.knownRoomIds.contains(roomId)) return false;
        final target = NeuraRoom.fromId(roomId);
        if (target.id != roomId) return false;
        final approved = await _confirmToolAction(
          title: 'Open ${target.title}?',
          message: 'Neura suggested changing rooms. The app will navigate '
              'only if you approve this request.',
          approveLabel: 'Open room',
        );
        if (!approved || !mounted) return false;
        await NeuraShell.of(context).setRoom(target);
        if (!mounted) return false;
        setState(() {
          _activeAgent = AgentSelectionService.instance.resolveAgent(target);
        });
        await AppLog.instance.info('dispatch_intent', {'room': roomId});
        return true;
      case NeuraChatPolicy.setTone:
        final tone = command.arguments['tone']?.toString() ?? '';
        if (!NeuraChatPolicy.knownTones.contains(tone)) return false;
        final approved = await _confirmToolAction(
          title: 'Change Neura’s tone?',
          message: 'Use the “$tone” presentation tone for this interaction?',
          approveLabel: 'Change tone',
        );
        if (!approved) return false;
        final applied = NeuraToneRuntime.instance.setTone(tone);
        await AppLog.instance.info('set_tone', {'tone': tone, 'applied': applied});
        return applied;
      default:
        return false;
    }
  }

  Future<bool> _confirmToolAction({
    required String title,
    required String message,
    required String approveLabel,
  }) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(approveLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _transcriptSnippet(List<NeuraChatTurn> history) {
    const maxTurns = 6;
    final recent = history.length > maxTurns
        ? history.sublist(history.length - maxTurns)
        : history;
    return recent
        .map((t) => '${t.isUser ? 'User' : 'Neura'}: ${t.text}')
        .join('\n');
  }

  void _toggleSpeech() {
    setState(() => _speechEnabled = !_speechEnabled);
    if (!_speechEnabled) {
      unawaited(NeuraTtsService.instance.stop());
    }
  }

  void _showAiDiagnostics() {
    final snapshot = NeuraAiService.instance.diagnosticsSnapshot;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI diagnostics',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text('Healthy: ${snapshot['healthy']}'),
              Text('Attempts: ${snapshot['attempts']}'),
              Text('Successes: ${snapshot['successes']}'),
              Text('Failures: ${snapshot['failures']}'),
              Text('Retries: ${snapshot['retries']}'),
              Text('Interruptions: ${snapshot['cancellations']}'),
              Text('Dropped tools: ${snapshot['tool_drops']}'),
              Text('Local fallbacks: ${snapshot['fallbacks']}'),
              if (snapshot['last_error'] != null) ...[
                const SizedBox(height: 8),
                Text('Last error: ${snapshot['last_error']}'),
              ],
              const SizedBox(height: 8),
              Text(snapshot['remedy']?.toString() ?? ''),
            ],
          ),
        ),
      ),
    );
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
          IconButton(
            tooltip: 'AI diagnostics',
            onPressed: _showAiDiagnostics,
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (line.imageBase64 != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.image,
                                      size: 16, color: Colors.white70),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                        line.text.isEmpty ? '…' : line.text),
                                  ),
                                ],
                              )
                            else
                              Text(line.text.isEmpty ? '…' : line.text),
                            if (line.interrupted) ...[
                              const SizedBox(height: 6),
                              const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.stop_circle_outlined,
                                      size: 14, color: Colors.white70),
                                  SizedBox(width: 4),
                                  Text(
                                    'Interrupted',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
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
                      enabled: true,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _listening
                            ? 'Listening…'
                            : (_busy
                                ? 'Type to interrupt Neura…'
                                : (_continuousMode
                                    ? 'Getting ready to listen…'
                                    : 'Talk to Neura…')),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Attach a photo',
                    onPressed: _busy ? null : _pickAndSendImage,
                    icon: const Icon(Icons.image_outlined),
                  ),
                  IconButton(
                    tooltip: _listening
                        ? 'Done — send it'
                        : (_busy
                            ? 'Interrupt and talk'
                            : 'Talk freely (hands-free)'),
                    onPressed: _beginVoiceBargeIn,
                    icon: Icon(
                      _listening ? Icons.mic : Icons.mic_none,
                      color: _listening ? Colors.redAccent : null,
                    ),
                  ),
                  IconButton(
                    tooltip: _busy ? 'Interrupt and send' : 'Send',
                    onPressed: _send,
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
  final String? utteranceId;
  final String? imageBase64;
  final String? imageMediaType;
  int seq;
  bool interrupted;

  _ChatLine(
    this.isUser,
    this.text, {
    this.agentId,
    this.utteranceId,
    this.imageBase64,
    this.imageMediaType,
    this.seq = 0,
    this.interrupted = false,
  });

  factory _ChatLine.user(
    String t, {
    String? utteranceId,
    String? imageBase64,
    String? imageMediaType,
  }) =>
      _ChatLine(
        true,
        t,
        utteranceId: utteranceId,
        imageBase64: imageBase64,
        imageMediaType: imageMediaType,
      );

  factory _ChatLine.bot(
    String t, {
    String? agentId,
    String? utteranceId,
  }) =>
      _ChatLine(false, t, agentId: agentId, utteranceId: utteranceId);
}
