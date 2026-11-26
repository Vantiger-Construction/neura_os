import 'dart:async';
import '../profiles/local_profile_service.dart';
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:uuid/uuid.dart';

import '../encrypted_memory/companion_memory_service.dart';
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
import 'emotion_analysis_service.dart';
import 'neura_offline_prompt.dart';
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
import 'neura_offline_budget.dart';
import 'neura_companion_presence.dart';
import '../reference/neura_reference_shelf.dart';

typedef NeuraToolCommandHandler = FutureOr<bool> Function(
  NeuraToolCommand command,
);

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
  NeuraAiService._()
      : _modelRouter = NeuraSecureModelRouter(),
        _configuredReader = null;
  NeuraAiService.forTesting({
    required NeuraSecureModelRouter modelRouter,
    required bool Function() configuredReader,
    NeuraOllamaChat? ollama,
  })  : _modelRouter = modelRouter,
        _configuredReader = configuredReader,
        _ollama = ollama;
  static final NeuraAiService instance = NeuraAiService._();

  static const _maxToolRounds = 4;

  final NeuraLlmDiagnostics _diagnostics = NeuraLlmDiagnostics.instance;
  final NeuraSecureModelRouter _modelRouter;
  final bool Function()? _configuredReader;
  NeuraGenerationCancel? _activeCancel;
  String? _activeGenerationId;
  NeuraOllamaChat? _ollama;

  bool get isConfigured {
    final configuredReader = _configuredReader;
    if (configuredReader != null) return configuredReader();
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

  /// Primes the on-device model for the next ordinary offline reply in
  /// [roomId]: loads it and pre-evaluates the exact system prompt and tools
  /// [streamReply] will send, with no conversation text. Call when the user
  /// opens offline chat, so the work overlaps with them typing or speaking.
  /// [withTools] must match whether that reply will pass an `onToolCommand`.
  /// Best effort and silent: a warm-up that cannot run changes nothing.
  Future<void> warmOffline({
    String agentId = AgentPersonaCatalog.generalId,
    String roomId = 'penthouse',
    NeuraConversationMode conversationMode = NeuraConversationMode.balanced,
    bool withTools = true,
  }) async {
    try {
      final profiles = LocalProfileService.instance;
      final profileSession = profiles.enabled;
      if (profileSession && !profiles.canUseSession) return;
      final audience = profileSession
          ? profiles.active!.audience
          : NeuraAudienceService.instance.currentAudience;
      // Must match the arguments streamReply uses for an offline reply
      // without companion notes; a test pins the two prompts together.
      final systemPrompt = await NeuraPromptBuilder.instance.buildSystemMessage(
        agentId: agentId,
        audience: audience,
        module: roomId,
        includePersistentMemory: false,
        memoryPermission: null,
        includeCurrentMood: false,
        includePersonality: false,
        conversationMode: conversationMode,
        maxMemoryBytes: 1500,
      );
      final tools = !profileSession && withTools
          ? _offlineTools(
              NeuraChatPolicy.advertisedTools(NeuraChatPolicy.forRoom(roomId)),
            )
          : const <Map<String, dynamic>>[];
      await (_ollama ??= NeuraOllamaChat()).warm(
        system: _offlineSystemWithTools(
          '$systemPrompt$kNeuraOfflineSystemSuffix',
          tools,
        ),
        tools: tools,
      );
    } catch (_) {
      // Warm-up is an optimization only.
    }
  }

  static List<Map<String, dynamic>> _offlineTools(
    List<Map<String, dynamic>> advertised,
  ) =>
      [
        for (final tool in advertised)
          {
            'name': tool['name'],
            'description': tool['description'],
            'parameters': tool['input_schema'],
          },
      ];

  static String _offlineSystemWithTools(
    String offlineSystem,
    List<Map<String, dynamic>> tools,
  ) =>
      tools.isEmpty
          ? offlineSystem
          : offlineSystem.replaceFirst(
              'No tools are available.',
              'Use a tool only when the user clearly asks for that action; '
                  'the user must confirm each one.',
            );

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
    CompanionMemoryPermission? memoryPermission,
    bool historyIncludesPrivateContext = false,
    NeuraConversationMode conversationMode = NeuraConversationMode.balanced,
    bool localOllama = false,
    NeuraOfflineBudget offlineBudget = NeuraOfflineBudget.standard,
    String threadContext = '',
    NeuraReferenceGrant? offlineReference,
    int? offlineMaxTokens,
  }) async* {
    _throwIfCloudBlocked();
    final profiles = LocalProfileService.instance;
    final profileEpoch = profiles.epoch;
    final profileSession = profiles.enabled;
    if (profileSession &&
        (!profiles.canUseSession ||
            selectedContext != null ||
            includePermittedMemory ||
            memoryPermission != null ||
            historyIncludesPrivateContext ||
            offlineReference != null ||
            history.any((t) => t.imageBase64 != null))) {
      throw StateError(
          'Profile chat accepts only this session’s visible text.');
    }
    if (!localOllama && !isConfigured) {
      throw StateError('Configure the AI provider key in Settings.');
    }
    if (offlineReference != null &&
        (!localOllama ||
            history.length != 1 ||
            !history.single.isUser ||
            history.single.text != offlineReference.question ||
            threadContext.isNotEmpty)) {
      throw StateError('References require a dedicated local question.');
    }
    // Approved companion notes and earlier private-context replies may reach
    // the on-device model: nothing leaves the computer. Selected files and
    // images remain cloud-only features.
    if (localOllama &&
        (selectedContext != null ||
            (offlineReference != null &&
                (includePermittedMemory || historyIncludesPrivateContext)) ||
            history.any((t) => t.imageBase64 != null))) {
      throw StateError(
        'Offline Ollama currently supports text chat and approved notes only.',
      );
    }

    final id = generationId ?? const Uuid().v4();
    final cancel = NeuraGenerationCancel(id);

    // Barge-in: a newer user turn always supersedes the previous generation.
    cancelActiveGeneration();
    _activeCancel = cancel;
    _activeGenerationId = id;
    final thinking = NeuraCompanionPresence.instance.acquireThinking();
    unawaited(cancel.whenCancelled.then((_) => thinking?.release()));

    void checkProfile() {
      if (profiles.enabled != profileSession ||
          profiles.epoch != profileEpoch ||
          (profileSession && !profiles.canUseSession)) {
        cancel.cancel();
      }
    }

    profiles.addListener(checkProfile);
    checkProfile();
    final policy = profileSession
        ? NeuraChatRoomPolicy(
            roomId: roomId, persistMemory: false, allowedTools: const {})
        : NeuraChatPolicy.forRoom(roomId);
    final advertisedTools = NeuraChatPolicy.advertisedTools(policy);
    final useMemory = policy.persistMemory && includePermittedMemory;
    void checkReference() {
      try {
        offlineReference?.requireCurrent();
      } catch (_) {
        cancel.cancel();
      }
    }

    if (offlineReference != null) {
      offlineReference.shelf.addListener(checkReference);
      unawaited(cancel.whenCancelled.then((_) => offlineReference.revoke()));
    }
    void checkMemory() {
      if (!useMemory || memoryPermission == null) return;
      try {
        memoryPermission.requireCurrent();
      } catch (_) {
        cancel.cancel();
      }
    }

    if (useMemory && memoryPermission != null) {
      memoryPermission.service.addListener(checkMemory);
      unawaited(cancel.whenCancelled.then((_) => memoryPermission.revoke()));
    }

    try {
      if (useMemory && memoryPermission == null) {
        throw StateError(
          'Authorize companion-note recall for this reply first.',
        );
      }
      final blocked = await _checkGuardrails(history);
      cancel.throwIfCancelled();
      if (blocked != null) {
        yield blocked;
        return;
      }
      final audience = profileSession
          ? profiles.active!.audience
          : NeuraAudienceService.instance.currentAudience;

      final systemPrompt = await NeuraPromptBuilder.instance.buildSystemMessage(
        agentId: agentId,
        audience: audience,
        module: roomId,
        includePersistentMemory: useMemory,
        memoryPermission: memoryPermission,
        includeCurrentMood: !localOllama && !profileSession,
        // Wit and knowledge guidance needs the cloud model and room in its
        // prompt; the on-device prompt is at its native byte limit.
        includePersonality: !localOllama,
        conversationMode: conversationMode,
        // The on-device model has a much smaller context window.
        maxMemoryBytes: localOllama ? 1500 : null,
      );
      cancel.throwIfCancelled();
      if (localOllama) {
        // No tools, persistent memory, swarm review or cloud routing. A
        // dedicated reference grant permits only its displayed passages.
        // The standard charter, room framing, audience and input guardrails
        // still apply. Offline chat never falls through to the cloud router.
        checkReference();
        cancel.throwIfCancelled();
        final localMessages = offlineReference == null
            ? history.map((turn) => turn.toJson()).toList()
            : <Map<String, dynamic>>[
                {'role': 'user', 'content': offlineReference.consume()}
              ];
        final recent = offlineBudget.retain(
          localMessages,
          threadContext: threadContext,
        );
        // The small local model reads subtext less reliably and only sees a
        // few recent turns, so pass one tentative, locally computed line: how
        // the newest message sounds, or else a clear feeling from an earlier
        // turn that has scrolled out of its view. Nothing is stored; the cue
        // is bounded by EmotionRead.maxCueBytes.
        var emotionCue = '';
        if (history.isNotEmpty && history.last.isUser) {
          final visible = offlineReference == null
              ? EmotionAnalysisService.visibleTailLength(localMessages, recent)
              : 0;
          final hidden = offlineReference == null
              ? history
                  .take(history.length - visible)
                  .where((turn) => turn.isUser)
                  .map((turn) => turn.text)
                  .toList()
              : const <String>[];
          emotionCue = const EmotionAnalysisService().offlineCue(
            newest: history.last.text,
            hiddenUserTurns: hidden,
          );
        }
        // The cue goes after the newest turn, not into the system prompt: a
        // system prompt that changes every turn forces the local model to
        // re-read the whole conversation (minutes on a laptop CPU).
        final offlineSystem = '$systemPrompt$kNeuraOfflineSystemSuffix';
        if (offlineReference == null) {
          // Ordinary chat streams whole sentences, each screened before it is
          // shown or spoken, so speech starts after the first sentence.
          // The room's tools are offered too; every call is re-checked against
          // the room policy and confirmed by the user before it runs.
          final offlineTools = !profileSession && onToolCommand != null
              ? _offlineTools(advertisedTools)
              : const <Map<String, dynamic>>[];
          final system = _offlineSystemWithTools(offlineSystem, offlineTools);
          var messages = recent;
          var actions = 0;
          for (var round = 0;; round++) {
            NeuraOllamaTurn? turn;
            yield* _streamOfflineSentences(
              system: system,
              messages: messages,
              cancel: cancel,
              tools: offlineTools,
              cue: emotionCue,
              maxTokens: offlineMaxTokens,
              onTurn: (value) => turn = value,
            );
            final calls = turn?.toolCalls ?? const <NeuraOllamaToolCall>[];
            if (calls.isEmpty) return;
            if (round >= _maxToolRounds) {
              yield '\nI reached the action limit for this turn. Please review '
                  'the result before continuing.';
              return;
            }
            final results = <Map<String, dynamic>>[];
            for (final call in calls) {
              cancel.throwIfCancelled();
              if (++actions > 8) {
                throw const NeuraStreamFailure(
                  'The action limit was reached.',
                );
              }
              final result = await _executeTool(
                call.name,
                call.arguments,
                policy: policy,
                cancel: cancel,
                onToolCommand: onToolCommand,
              );
              results.add({
                'role': 'tool',
                'content': NeuraOllamaTurn.boundToolResult(result),
                'tool_name': call.name,
              });
            }
            cancel.throwIfCancelled();
            if (turn!.text.trim().isNotEmpty) yield '\n\n';
            messages = [
              ...messages,
              {
                'role': 'assistant',
                'content': turn!.text,
                'tool_calls': [for (final call in calls) call.toJson()],
              },
              ...results,
            ];
          }
        }
        // Reference answers are verified as a whole before any prose is shown.
        final text = await (_ollama ??= NeuraOllamaChat()).reply(
          system: offlineSystem,
          messages: recent,
          cancel: cancel,
          cue: emotionCue,
        );
        cancel.throwIfCancelled();
        checkReference();
        cancel.throwIfCancelled();
        // Validate and decode reference evidence before screening the complete
        // display text, including JSON-escaped source characters. No model
        // prose is released; quotation matching proves identity, not truth.
        final displayText = offlineReference.formatVerifiedReply(text);
        final postBlocked = await _checkGuardrails([
          NeuraChatTurn(isUser: true, text: displayText),
        ]);
        checkReference();
        cancel.throwIfCancelled();
        yield postBlocked ?? displayText;
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
        checkMemory();
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
          requestApproval: (preview) async {
            checkMemory();
            cancel.throwIfCancelled();
            final approved = await (requestCloudApproval ?? _denyCloudRequest)(
              preview,
            );
            checkMemory();
            cancel.throwIfCancelled();
            return approved;
          },
        )) {
          checkMemory();
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
              'The action limit or a duplicate action was reached.',
            );
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
      thinking?.release();
      if (offlineReference != null) {
        offlineReference.shelf.removeListener(checkReference);
        offlineReference.revoke();
      }
      profiles.removeListener(checkProfile);
      if (useMemory && memoryPermission != null) {
        memoryPermission.service.removeListener(checkMemory);
        memoryPermission.revoke();
      }
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
              ? 'Moving to "$room" when this reply ends.'
              : 'Did not move to "$room": already there, or not possible '
                  'right now.';

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
    if (LocalProfileService.instance.enabled) {
      throw StateError('Private summaries are unavailable in profile mode.');
    }
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

  /// Index just past the last complete sentence in [text] at or after [from],
  /// or [from] when none has completed. Sentence punctuation counts only once
  /// whitespace follows it, so "3.5" or a still-arriving "..." does not split.
  @visibleForTesting
  static int sentenceReleaseEnd(String text, int from) {
    for (var i = text.length - 1; i >= from; i--) {
      final char = text.codeUnitAt(i);
      if (char == 0x0A) return i + 1;
      if ((char == 0x2E || char == 0x21 || char == 0x3F) &&
          i + 1 < text.length &&
          (text.codeUnitAt(i + 1) == 0x20 || text.codeUnitAt(i + 1) == 0x0A)) {
        return i + 1;
      }
    }
    return from;
  }

  /// Offline reply released sentence by sentence. Each release is screened
  /// together with everything already shown, and the verified final reply is
  /// screened again, so no unscreened model prose reaches the screen or voice.
  /// A mid-reply block stops generation and shows the safe alternative.
  Stream<String> _streamOfflineSentences({
    required String system,
    required List<Map<String, dynamic>> messages,
    required NeuraGenerationCancel cancel,
    List<Map<String, dynamic>> tools = const [],
    String cue = '',
    int? maxTokens,
    void Function(NeuraOllamaTurn turn)? onTurn,
  }) async* {
    // A child token lets a guardrail block stop native generation without
    // reporting the turn as a user cancellation.
    final generation = NeuraGenerationCancel(cancel.generationId);
    unawaited(cancel.whenCancelled.then((_) => generation.cancel()));
    final partials = StreamController<String>();
    final reply = (_ollama ??= NeuraOllamaChat())
        .reply(
          system: system,
          messages: messages,
          cancel: generation,
          onPartial: partials.add,
          tools: tools,
          cue: cue,
          maxTokens: maxTokens,
        )
        .whenComplete(partials.close);
    reply.ignore(); // Awaited below; avoid an unhandled-error report meanwhile.
    var released = '';
    var finished = false;
    try {
      String? blocked;
      await for (final soFar in partials.stream) {
        final end = sentenceReleaseEnd(soFar, released.length);
        if (end <= released.length) continue;
        final candidate = soFar.substring(0, end);
        blocked = await _checkGuardrails([
          NeuraChatTurn(isUser: true, text: candidate),
        ]);
        cancel.throwIfCancelled();
        if (blocked != null) break;
        yield candidate.substring(released.length);
        released = candidate;
      }
      if (blocked != null) {
        generation.cancel();
        try {
          await reply;
        } catch (_) {
          // The stopped request's outcome is irrelevant to the safe reply.
        }
        cancel.throwIfCancelled();
        finished = true;
        yield released.isEmpty ? blocked : '\n\n$blocked';
        return;
      }
      final raw = await reply;
      cancel.throwIfCancelled();
      // With tools the native reply is an envelope; partials were its text.
      final turn = tools.isEmpty
          ? NeuraOllamaTurn(raw, const [])
          : NeuraOllamaTurn.parse(raw);
      final text = turn.text;
      // A reply cut at the token cap ends at its last complete sentence, and
      // may drop a cut-off lead-in line that was already released.
      if (!text.startsWith(released) && !released.startsWith(text)) {
        throw StateError('Offline reply changed while streaming.');
      }
      final postBlocked = await _checkGuardrails([
        NeuraChatTurn(isUser: true, text: text),
      ]);
      cancel.throwIfCancelled();
      finished = true;
      if (postBlocked != null) {
        // A blocked reply never hands its tool calls to the caller.
        yield released.isEmpty ? postBlocked : '\n\n$postBlocked';
      } else {
        if (text.length > released.length) {
          yield text.substring(released.length);
        }
        onTurn?.call(turn);
      }
    } finally {
      // A listener that stops early must not leave native generation running.
      if (!finished) generation.cancel();
    }
  }

  /// Runs the outgoing user message through Guardrails before it reaches the
  /// LLM. Returns a safe-alternative message to show instead if blocked.
  Future<String?> _checkGuardrails(List<NeuraChatTurn> history) async {
    if (history.isEmpty) return null;
    final lastMessage = history.last.text;
    final scan = CrisisTextScan.of(lastMessage);

    if (LocalProfileService.instance.enabled) {
      // Only the current message and selected age group. No installation-wide
      // mood, focus, audience or storm-event read/write enters this path.
      if (!LocalProfileService.instance.canUseSession) {
        throw StateError('Profile session expired.');
      }
      final decision = Guardrails().evaluate(
          context: NeuraContextSnapshot(
              now: DateTime.now(),
              userInFocusMode: false,
              isMinor: LocalProfileService.instance.active!.audience !=
                  NeuraAudience.adult,
              distressScore: scan.crisis ? 0.95 : 0.1),
          proposal: NeuraProposal(
              type: ProposalType.prompt,
              id: 'profile_chat_message',
              message: lastMessage,
              options: const ['send', 'no_thanks']));
      if (decision.allow) return null;
      return '${decision.safeAlternative?.message ?? decision.reason}'
          '${scan.crisis ? '\n\n${SupportResources.forLocale(PlatformDispatcher.instance.locale.toLanguageTag())}' : ''}';
    }
    final moodEntries = await MoodStore.instance.getAll();
    if (LocalProfileService.instance.enabled) {
      throw StateError('Profile boundary changed.');
    }
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
    if (supportMode && !LocalProfileService.instance.enabled) {
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
