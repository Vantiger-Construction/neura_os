import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:uuid/uuid.dart';

import '../after_storm/models/storm_event.dart';
import '../weekly/services/weekly_snapshot_bridge.dart';
import '../guardrails/guardrails.dart';
import '../guardrails/guardrails_types.dart';
import '../guardrails/support_resources.dart';
import '../modules/mood/mood_store.dart';
import '../persona/agents/agent_persona_catalog.dart';
import '../persona/models/neura_audience.dart';
import '../persona/services/neura_audience_service.dart';
import '../persona/services/neura_prompt_builder.dart';
import '../persona/services/neura_conversation_mode.dart';
import '../reliability/safe_boot.dart';
import '../relationships/services/crisis_text_scan.dart';
import '../relationships/services/distress_detector.dart';
import '../src/modules/focus/focus_controller.dart';
import '../src/modules/focus/focus_mode.dart';
import 'crisis_playbook_surface.dart';
import 'neura_chat_policy.dart';
import 'neura_generation_cancel.dart';
import 'neura_llm_diagnostics.dart';
import 'neura_model_credentials.dart';
import 'neura_model_router.dart';
import 'neura_model_stream.dart';
import 'neura_selected_context.dart';
import 'neura_model_types.dart';
import 'neura_provider_credentials.dart';
import 'neura_ollama_chat.dart';

typedef NeuraToolCommandHandler = FutureOr<bool> Function(
    NeuraToolCommand command);

/// One turn in the conversation, in the shape the Messages API expects.
/// A user turn may optionally carry an image (base64-encoded) for vision.
class NeuraChatTurn {
  final bool isUser;
  final String text;
  final String? imageBase64;
  final String? imageMediaType;

  const NeuraChatTurn({
    required this.isUser,
    required this.text,
    this.imageBase64,
    this.imageMediaType,
  });

  Map<String, dynamic> toJson() {
    if (imageBase64 == null) {
      return {'role': isUser ? 'user' : 'assistant', 'content': text};
    }
    return {
      'role': isUser ? 'user' : 'assistant',
      'content': [
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': imageMediaType ?? 'image/jpeg',
            'data': imageBase64,
          },
        },
        if (text.isNotEmpty) {'type': 'text', 'text': text},
      ],
    };
  }
}

/// Provider-neutral chat orchestration through the secure model router.
///
/// Features deliberately kept in one place:
/// - SSE text streaming
/// - cooperative barge-in/cancellation
/// - room-scoped model tools with execution-time re-validation
/// - persistent-memory privacy gating via [NeuraPromptBuilder]
/// - fallback only before any streamed output, with separate approval
/// - process-local health diagnostics
class NeuraAiService {
  NeuraAiService._();
  static final NeuraAiService instance = NeuraAiService._();

  static const _maxToolRounds = 4;

  final NeuraLlmDiagnostics _diagnostics = NeuraLlmDiagnostics.instance;
  final NeuraSecureModelRouter _modelRouter = NeuraSecureModelRouter();
  NeuraGenerationCancel? _activeCancel;
  String? _activeGenerationId;
  NeuraOllamaChat? _ollama;

  bool get isConfigured {
    if (NeuraProviderCredentials.instance.hasKey) return true;
    return NeuraModelCredentials.instance.configured.value.isNotEmpty;
  }

  bool get cloudRequestsAllowed => !SafeBoot.instance.safeMode.value;
  String? get activeGenerationId => _activeGenerationId;
  Map<String, dynamic> get diagnosticsSnapshot => {
        ..._diagnostics.snapshot(),
        'provider_health': _modelRouter.providerHealthSnapshot,
      };

  /// Cancels the currently streamed reply, if any. This is safe to call when
  /// no generation is active and is the primitive used by the chat UI for
  /// user barge-in.
  void cancelActiveGeneration() {
    final active = _activeCancel;
    if (active == null || active.isCancelled) return;
    active.cancel();
    _diagnostics.recordCancellation();
  }

  /// Streams incremental text deltas for a reply to [history].
  ///
  /// Starting a new generation automatically cancels the previous one. Tool
  /// definitions are selected from [roomId], and every model-requested tool
  /// is checked against the same policy again immediately before execution.
  /// [historyIncludesPrivateContext] retains the privacy restriction on
  /// answers derived from files, memory or private actions in earlier turns.
  Stream<String> streamReply(
    List<NeuraChatTurn> history, {
    String agentId = AgentPersonaCatalog.generalId,
    String roomId = 'penthouse',
    String? generationId,
    NeuraToolCommandHandler? onToolCommand,
    NeuraCloudApprovalHandler? requestCloudApproval,
    NeuraSelectedContext? selectedContext,
    bool includePermittedMemory = false,
    bool historyIncludesPrivateContext = false,
    NeuraConversationMode conversationMode = NeuraConversationMode.balanced,
    bool localOllama = false,
  }) async* {
    _throwIfCloudBlocked();
    if (!localOllama && !isConfigured) {
      throw StateError('Configure the AI provider key in Settings.');
    }
    if (localOllama &&
        (selectedContext != null ||
            includePermittedMemory ||
            historyIncludesPrivateContext ||
            history.any((t) => t.imageBase64 != null))) {
      throw StateError(
          'Offline Ollama currently supports visible text chat only.');
    }

    final id = generationId ?? const Uuid().v4();
    final cancel = NeuraGenerationCancel(id);

    // Barge-in: a newer user turn always supersedes the previous generation.
    cancelActiveGeneration();
    _activeCancel = cancel;
    _activeGenerationId = id;

    final policy = NeuraChatPolicy.forRoom(roomId);
    final advertisedTools = NeuraChatPolicy.advertisedTools(policy);

    try {
      final blocked = await _checkGuardrails(history);
      cancel.throwIfCancelled();
      if (blocked != null) {
        yield blocked;
        return;
      }
      final audience = NeuraAudienceService.instance.currentAudience;

      final useMemory = policy.persistMemory && includePermittedMemory;
      final systemPrompt = await NeuraPromptBuilder.instance.buildSystemMessage(
        agentId: agentId,
        audience: audience,
        module: roomId,
        includePersistentMemory: useMemory,
        includeCurrentMood: !localOllama,
        conversationMode: conversationMode,
      );
      cancel.throwIfCancelled();
      if (localOllama) {
        // No tools, approved sources, memory, swarm review or cloud routing.
        // The standard charter, room framing, audience and input guardrails
        // still apply. Offline chat never falls through to the cloud router.
        final recent = history.length > 8
            ? history.sublist(history.length - 8)
            : List<NeuraChatTurn>.of(history);
        // Trim older whole turns before crossing the platform channel; Rust
        // independently revalidates the same byte/count caps.
        while (recent.length > 1 &&
            recent.fold<int>(
                    0, (sum, turn) => sum + utf8.encode(turn.text).length) >
                1500) {
          recent.removeAt(0);
        }
        final text = await (_ollama ??= NeuraOllamaChat()).reply(
          system:
              '$systemPrompt\n\nYou are running offline. Do not claim web access, '
              'saved memories or completed actions. Offer everyday support; do not '
              'diagnose or advise medication changes. No tools are available.',
          messages: recent.map((t) => t.toJson()).toList(),
          cancel: cancel,
        );
        cancel.throwIfCancelled();
        final postBlocked = await _checkGuardrails([
          NeuraChatTurn(isUser: true, text: text),
        ]);
        cancel.throwIfCancelled();
        yield postBlocked ?? text;
        return;
      }
      final messages = history.map((t) => t.toJson()).toList();
      if (selectedContext != null) {
        messages.add({'role': 'user', 'content': selectedContext.toMessage()});
      }
      NeuraModelProvider? activeProvider;
      var toolResultsArePrivate = false;
      var toolRounds = 0;
      var actionCount = 0;
      final seenCallIds = <String>{};
      while (true) {
        cancel.throwIfCancelled();
        _diagnostics.recordAttempt();
        final latency = Stopwatch()..start();
        var firstTokenRecorded = false;
        NeuraTurnComplete? completed;
        await for (final event in _modelRouter.stream(
          NeuraModelRequest(
            systemPrompt: systemPrompt,
            messages: messages,
            purpose: toolRounds == 0
                ? 'chat reply'
                : 'continue after approved actions',
            includesPrivateContext: historyIncludesPrivateContext ||
                useMemory ||
                selectedContext != null ||
                toolResultsArePrivate,
          ),
          tools: advertisedTools,
          cancel: cancel,
          provider: activeProvider,
          requestApproval: requestCloudApproval ?? _denyCloudRequest,
        )) {
          cancel.throwIfCancelled();
          if (event is NeuraTextDelta) {
            if (!firstTokenRecorded && event.text.isNotEmpty) {
              firstTokenRecorded = true;
              _diagnostics.recordFirstToken(latency.elapsed);
            }
            yield event.text;
          }
          if (event is NeuraTurnComplete) completed = event;
        }
        if (completed == null) {
          throw const NeuraStreamFailure('Reply did not complete.');
        }
        _diagnostics.recordCompletion(latency.elapsed);
        _diagnostics.recordSuccess();
        activeProvider = completed.provider;
        final blocks = completed.blocks;
        if (!blocks.any((block) => block['type'] == 'tool_use')) break;
        if (++toolRounds > _maxToolRounds) {
          yield '\nI reached the action limit for this turn. Please review the result before continuing.';
          break;
        }
        messages.add({
          'role': 'assistant',
          'content': blocks,
          if (completed.openAiOutput.isNotEmpty)
            'openai_output': completed.openAiOutput,
        });
        final toolResults = <Map<String, dynamic>>[];
        for (final block in blocks) {
          _throwIfCloudBlocked();
          cancel.throwIfCancelled();
          if (block['type'] != 'tool_use') continue;
          final callId = block['id'];
          if (callId is! String ||
              callId.isEmpty ||
              !seenCallIds.add(callId) ||
              ++actionCount > 8) {
            throw const NeuraStreamFailure(
                'The action limit or a duplicate action was reached.');
          }
          final name = block['name']?.toString() ?? '';
          toolResultsArePrivate = toolResultsArePrivate ||
              name == NeuraChatPolicy.getMoodHistory ||
              name == NeuraChatPolicy.logMoodEntry;
          final resultText = await _executeTool(
            name,
            (block['input'] as Map<String, dynamic>?) ?? const {},
            policy: policy,
            cancel: cancel,
            onToolCommand: onToolCommand,
          );
          toolResults.add({
            'type': 'tool_result',
            'tool_use_id': block['id'],
            'content': resultText,
          });
        }
        if (toolResults.isEmpty) break;
        messages.add({'role': 'user', 'content': toolResults});
      }
    } on NeuraGenerationCancelled {
      rethrow;
    } catch (error) {
      _diagnostics.recordFailure(error);
      rethrow;
    } finally {
      if (identical(_activeCancel, cancel)) {
        _activeCancel = null;
        _activeGenerationId = null;
      }
    }
  }

  /// Executes a tool call after re-validating it against the room policy.
  /// Never throws for normal model mistakes; failures become tool-result text
  /// so the model can recover without breaking the conversation.
  Future<String> _executeTool(
    String name,
    Map<String, dynamic> input, {
    required NeuraChatRoomPolicy policy,
    required NeuraGenerationCancel cancel,
    NeuraToolCommandHandler? onToolCommand,
  }) async {
    cancel.throwIfCancelled();

    if (!policy.allowsTool(name)) {
      _diagnostics.recordToolDrop();
      return 'Tool unavailable in ${policy.roomId}: $name';
    }

    try {
      switch (name) {
        case NeuraChatPolicy.getMoodHistory:
          final limitRaw = (input['limit'] as num?)?.toInt() ?? 10;
          final limit = limitRaw.clamp(1, 50).toInt();
          if (onToolCommand == null) {
            return 'Tool unavailable: user confirmation UI is missing.';
          }
          final approved = await onToolCommand(
            NeuraToolCommand(NeuraChatPolicy.getMoodHistory, {'limit': limit}),
          );
          if (!approved) {
            return 'The user did not approve sharing mood history.';
          }
          cancel.throwIfCancelled();
          _throwIfCloudBlocked();
          final entries = await MoodStore.instance.getAll();
          cancel.throwIfCancelled();
          final recent = entries.length > limit
              ? entries.sublist(entries.length - limit)
              : entries;
          if (recent.isEmpty) return 'No mood entries recorded yet.';
          return recent
              .map(
                (e) =>
                    '${e.timestamp.toIso8601String()}: mood ${e.mood0to10}/10',
              )
              .join('\n');

        case NeuraChatPolicy.logMoodEntry:
          final moodRaw = input['mood0to10'];
          if (moodRaw is! num) {
            return 'Tool error: mood0to10 is required.';
          }
          final mood = moodRaw.round().clamp(0, 10).toInt();
          final note = (input['note'] as String?) ?? '';
          if (onToolCommand == null) {
            return 'Tool unavailable: user confirmation UI is missing.';
          }
          final approved = await onToolCommand(
            NeuraToolCommand(NeuraChatPolicy.logMoodEntry, {
              'mood0to10': mood,
              'note': note,
            }),
          );
          cancel.throwIfCancelled();
          return approved
              ? 'The user approved and saved mood $mood/10 locally.'
              : 'The user did not approve saving this mood check-in.';

        case NeuraChatPolicy.dispatchIntent:
          final room = input['room']?.toString() ?? '';
          if (!NeuraChatPolicy.knownRoomIds.contains(room)) {
            return 'Tool error: unknown room "$room".';
          }
          if (onToolCommand == null) {
            return 'Tool error: navigation runtime is unavailable.';
          }
          final approved = await onToolCommand(
            NeuraToolCommand(NeuraChatPolicy.dispatchIntent, {'room': room}),
          );
          cancel.throwIfCancelled();
          return approved
              ? 'The user approved navigation to "$room".'
              : 'The user did not approve navigation to "$room".';

        case NeuraChatPolicy.setTone:
          final tone = input['tone']?.toString() ?? '';
          if (!NeuraChatPolicy.knownTones.contains(tone)) {
            return 'Tool error: unknown tone "$tone".';
          }
          if (onToolCommand == null) {
            return 'Tool error: tone runtime is unavailable.';
          }
          final approved = await onToolCommand(
            NeuraToolCommand(NeuraChatPolicy.setTone, {'tone': tone}),
          );
          cancel.throwIfCancelled();
          return approved
              ? 'The user approved tone "$tone".'
              : 'The user did not approve changing tone.';

        default:
          _diagnostics.recordToolDrop();
          return 'Unknown tool: $name';
      }
    } on NeuraGenerationCancelled {
      rethrow;
    } catch (error) {
      return 'Tool error: $error';
    }
  }

  /// Generated summaries use the same constitution and per-request approval.
  /// A background caller without a visible approval handler remains blocked.
  Future<String> completeOnce(
    String userPrompt, {
    required String agentId,
    NeuraCloudApprovalHandler? requestCloudApproval,
  }) async {
    _throwIfCloudBlocked();
    final history = [NeuraChatTurn(isUser: true, text: userPrompt)];
    final blocked = await _checkGuardrails(history);
    if (blocked != null) throw NeuraGuardrailBlocked(blocked);
    final prompt = await NeuraPromptBuilder.instance.buildSystemMessage(
      agentId: agentId,
      audience: NeuraAudienceService.instance.currentAudience,
      includePersistentMemory: false,
    );
    _diagnostics.recordAttempt();
    final latency = Stopwatch()..start();
    late final NeuraModelResponse response;
    try {
      response = await _modelRouter.complete(
        NeuraModelRequest(
          systemPrompt: prompt,
          messages: history.map((turn) => turn.toJson()).toList(),
          purpose: 'generated summary',
          includesPrivateContext: true,
        ),
        requestApproval: requestCloudApproval ?? _denyCloudRequest,
      );
      _diagnostics.recordFirstToken(latency.elapsed);
      _diagnostics.recordCompletion(latency.elapsed);
      _diagnostics.recordSuccess();
    } catch (error) {
      _diagnostics.recordFailure(error);
      rethrow;
    }
    final postBlocked = await _checkGuardrails([
      NeuraChatTurn(isUser: true, text: response.text),
    ]);
    if (postBlocked != null) throw NeuraGuardrailBlocked(postBlocked);
    return response.text;
  }

  Future<bool> _denyCloudRequest(NeuraCloudRequestPreview _) async {
    throw const NeuraCloudApprovalDenied();
  }

  void _throwIfCloudBlocked() {
    if (!cloudRequestsAllowed) {
      throw StateError(
        'Cloud AI is unavailable while Neura is running in Safe Mode.',
      );
    }
  }

  /// Runs the outgoing user message through Guardrails before it reaches the
  /// LLM. Returns a safe-alternative message to show instead if blocked.
  Future<String?> _checkGuardrails(List<NeuraChatTurn> history) async {
    if (history.isEmpty) return null;
    final lastMessage = history.last.text;
    final scan = CrisisTextScan.of(lastMessage);

    final moodEntries = await MoodStore.instance.getAll();
    final recentEntries = moodEntries.length > 10
        ? moodEntries.sublist(moodEntries.length - 10)
        : moodEntries;
    final recentMoods = recentEntries
        .map((e) => ((e.mood0to10 - 5) / 2.5).round().clamp(-2, 2).toInt())
        .toList(growable: false);
    final signal = DistressDetector().detect(
      recentMoods: recentMoods,
      appOpensLastHour: 0,
      lotsOfNegativeWords: scan.distress,
    );

    await NeuraAudienceService.instance.load();
    final isMinor =
        NeuraAudienceService.instance.currentAudience != NeuraAudience.adult;

    final snapshot = NeuraContextSnapshot(
      now: DateTime.now(),
      userInFocusMode:
          FocusController.instance.state.value.mode != FocusMode.off,
      isMinor: isMinor,
      distressScore: scan.crisis ? 0.95 : (signal.active ? 0.9 : 0.1),
    );

    final proposal = NeuraProposal(
      type: ProposalType.prompt,
      id: 'chat_message',
      message: lastMessage,
      options: const ['send', 'no_thanks'],
    );

    final decision = Guardrails().evaluate(
      context: snapshot,
      proposal: proposal,
    );
    if (decision.allow) return null;

    final supportMode = scan.crisis || signal.active;
    if (supportMode) {
      try {
        await WeeklySnapshotBridge.instance.logStormEvent(
          StormEvent(
            id: const Uuid().v4(),
            timestamp: DateTime.now(),
            intensity: 'medium',
            primaryFeeling: 'distressed',
            shortSummary: 'Distress detected during a chat conversation.',
            needNow: 'support',
            safetyRisk: true,
            meta: {
              'source': 'chat_guardrail',
              'reasons': [
                if (scan.crisis) 'Explicit crisis language detected.',
                ...signal.reasons,
              ],
            },
          ),
        );
      } catch (_) {
        // Local event persistence must never prevent an immediate support
        // response from reaching the person.
      }
    }

    var message = decision.safeAlternative?.message ?? decision.reason;
    final reasonLower = decision.reason.toLowerCase();
    final isSupportDecision = supportMode ||
        reasonLower.contains('distress') ||
        reasonLower.contains('support');
    if (isSupportDecision) {
      message += '\n\nIf you need immediate help: '
          '${SupportResources.forLocale(PlatformDispatcher.instance.locale.toLanguageTag())}';
      final playbook = CrisisPlaybookSurface.select(scan, lastMessage);
      if (playbook != null) {
        message += '\n\n${CrisisPlaybookSurface.format(playbook)}';
      }
    }
    return message;
  }
}

class NeuraApiException implements Exception {
  final String message;
  final int? statusCode;

  NeuraApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class NeuraGuardrailBlocked implements Exception {
  final String guardrailMessage;
  NeuraGuardrailBlocked(this.guardrailMessage);
  @override
  String toString() => 'NeuraGuardrailBlocked: $guardrailMessage';
}
