import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
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
import '../reliability/safe_boot.dart';
import '../relationships/services/distress_detector.dart';
import '../src/modules/focus/focus_controller.dart';
import '../src/modules/focus/focus_mode.dart';
import 'neura_chat_policy.dart';
import 'neura_generation_cancel.dart';
import 'neura_llm_diagnostics.dart';
import 'neura_provider_credentials.dart';

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
      return {
        'role': isUser ? 'user' : 'assistant',
        'content': text,
      };
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

/// Raw HTTP client for the Anthropic Messages API.
///
/// Features deliberately kept in one place:
/// - SSE text streaming
/// - cooperative barge-in/cancellation
/// - room-scoped model tools with execution-time re-validation
/// - persistent-memory privacy gating via [NeuraPromptBuilder]
/// - bounded retry/backoff before any text is emitted
/// - process-local health diagnostics
class NeuraAiService {
  NeuraAiService._();
  static final NeuraAiService instance = NeuraAiService._();

  static const _model = 'claude-sonnet-5';
  static const _maxTokens = 2048;
  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  static const _maxToolRounds = 4;
  static const _maxRetries = 3;
  static const _initialBackoffMs = 350;
  static const _maxBackoffMs = 4000;
  static const _requestTimeout = Duration(seconds: 30);
  static const _retryableStatuses = {429, 500, 502, 503, 529};

  final NeuraLlmDiagnostics _diagnostics = NeuraLlmDiagnostics.instance;
  NeuraGenerationCancel? _activeCancel;
  String? _activeGenerationId;

  String get _apiKey => NeuraProviderCredentials.instance.apiKey;
  bool get isConfigured => NeuraProviderCredentials.instance.hasKey;
  bool get cloudRequestsAllowed => !SafeBoot.instance.safeMode.value;
  String? get activeGenerationId => _activeGenerationId;
  Map<String, dynamic> get diagnosticsSnapshot => _diagnostics.snapshot();

  /// Cancels the currently streamed reply, if any. This is safe to call when
  /// no generation is active and is the primitive used by the chat UI for
  /// user barge-in.
  void cancelActiveGeneration() {
    final active = _activeCancel;
    if (active == null || active.isCancelled) return;
    active.cancel();
    _diagnostics.recordCancellation();
  }

  static List<Map<String, dynamic>> _systemBlock(String systemPrompt) => [
        {
          'type': 'text',
          'text': systemPrompt,
          'cache_control': {'type': 'ephemeral'},
        },
      ];

  /// Streams incremental text deltas for a reply to [history].
  ///
  /// Starting a new generation automatically cancels the previous one. Tool
  /// definitions are selected from [roomId], and every model-requested tool
  /// is checked against the same policy again immediately before execution.
  Stream<String> streamReply(
    List<NeuraChatTurn> history, {
    String agentId = AgentPersonaCatalog.generalId,
    String roomId = 'penthouse',
    String? generationId,
    NeuraToolCommandHandler? onToolCommand,
  }) async* {
    _throwIfCloudBlocked();
    if (!isConfigured) {
      throw StateError('Configure the AI provider key in Settings.');
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

      final systemPrompt = await NeuraPromptBuilder.instance.buildSystemMessage(
        agentId: agentId,
        includePersistentMemory: policy.persistMemory,
      );
      cancel.throwIfCancelled();

      final messages = history.map((t) => t.toJson()).toList();

      var toolRounds = 0;
      while (true) {
        cancel.throwIfCancelled();
        List<Map<String, dynamic>>? finishedBlocks;
        var stopReason = 'end_turn';

        await for (final event in _streamOneTurn(
          systemPrompt,
          messages,
          advertisedTools,
          cancel,
        )) {
          cancel.throwIfCancelled();
          if (event is _TextDelta) {
            yield event.text;
          } else if (event is _TurnComplete) {
            finishedBlocks = event.contentBlocks;
            stopReason = event.stopReason;
          }
        }

        final blocks = finishedBlocks;
        if (stopReason != 'tool_use' || blocks == null || blocks.isEmpty) {
          break;
        }
        if (++toolRounds > _maxToolRounds) break;

        messages.add({'role': 'assistant', 'content': blocks});

        final toolResults = <Map<String, dynamic>>[];
        for (final block in blocks) {
          _throwIfCloudBlocked();
          cancel.throwIfCancelled();
          if (block['type'] != 'tool_use') continue;
          final name = block['name']?.toString() ?? '';
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
    } finally {
      if (identical(_activeCancel, cancel)) {
        _activeCancel = null;
        _activeGenerationId = null;
      }
    }
  }

  /// Runs one streamed turn against the Messages API and yields text deltas.
  /// Retries are allowed only before text is emitted, preventing duplicate
  /// visible output after a mid-stream network failure.
  Stream<_StreamEvent> _streamOneTurn(
    String systemPrompt,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
    NeuraGenerationCancel cancel,
  ) async* {
    Object? lastError;

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      _throwIfCloudBlocked();
      cancel.throwIfCancelled();
      final client = http.Client();
      var emittedText = false;

      try {
        _throwIfCloudBlocked();
        _diagnostics.recordAttempt();
        final request = _buildStreamRequest(systemPrompt, messages, tools);
        final streamedResponse = await Future.any<http.StreamedResponse>([
          client.send(request).timeout(_requestTimeout),
          cancel.whenCancelled.then<http.StreamedResponse>((_) {
            client.close();
            throw NeuraGenerationCancelled(cancel.generationId);
          }),
        ]);
        cancel.throwIfCancelled();

        if (streamedResponse.statusCode != 200) {
          final body = await streamedResponse.stream
              .timeout(_requestTimeout)
              .transform(utf8.decoder)
              .join();
          final error = NeuraApiException(
            '${streamedResponse.statusCode}: $body',
            statusCode: streamedResponse.statusCode,
          );
          lastError = error;
          if (_canRetry(error) && attempt < _maxRetries) {
            _diagnostics.recordRetry();
            await cancel.delay(_retryDelay(attempt, streamedResponse.headers));
            continue;
          }
          throw error;
        }

        final blocksByIndex = <int, Map<String, dynamic>>{};
        final toolInputBuffers = <int, StringBuffer>{};
        var stopReason = 'end_turn';
        var buffer = '';

        await for (final chunk in streamedResponse.stream
            .timeout(_requestTimeout)
            .transform(utf8.decoder)) {
          _throwIfCloudBlocked();
          cancel.throwIfCancelled();
          buffer += chunk;
          final lines = buffer.split('\n');
          buffer = lines.removeLast();

          for (final line in lines) {
            if (!line.startsWith('data: ')) continue;
            final data = line.substring(6).trim();
            if (data.isEmpty) continue;

            final event = jsonDecode(data) as Map<String, dynamic>;
            switch (event['type']) {
              case 'content_block_start':
                final index = event['index'] as int;
                final block = event['content_block'] as Map<String, dynamic>;
                blocksByIndex[index] = Map<String, dynamic>.from(block);
                if (block['type'] == 'tool_use') {
                  toolInputBuffers[index] = StringBuffer();
                }
                break;

              case 'content_block_delta':
                final index = event['index'] as int;
                final delta = event['delta'] as Map<String, dynamic>?;
                if (delta?['type'] == 'text_delta') {
                  final text = delta!['text'] as String;
                  final block = blocksByIndex[index];
                  if (block != null && block['type'] == 'text') {
                    block['text'] = (block['text'] as String? ?? '') + text;
                  }
                  emittedText = true;
                  yield _TextDelta(text);
                } else if (delta?['type'] == 'input_json_delta') {
                  toolInputBuffers[index]
                      ?.write(delta!['partial_json'] as String? ?? '');
                }
                break;

              case 'content_block_stop':
                final index = event['index'] as int;
                final inputBuffer = toolInputBuffers[index];
                if (inputBuffer != null) {
                  var input = <String, dynamic>{};
                  final raw = inputBuffer.toString();
                  if (raw.trim().isNotEmpty) {
                    try {
                      input = jsonDecode(raw) as Map<String, dynamic>;
                    } catch (_) {
                      // Leave malformed model input empty. The executor will
                      // validate required arguments and return a tool error.
                    }
                  }
                  blocksByIndex[index]?['input'] = input;
                }
                break;

              case 'message_delta':
                final delta = event['delta'] as Map<String, dynamic>?;
                final reason = delta?['stop_reason'];
                if (reason != null) stopReason = reason as String;
                break;

              case 'error':
                final error = event['error'] as Map<String, dynamic>?;
                throw NeuraApiException(
                  error?['message']?.toString() ?? 'Unknown API error',
                );
            }
          }
        }

        cancel.throwIfCancelled();
        final orderedIndices = blocksByIndex.keys.toList()..sort();
        final contentBlocks =
            orderedIndices.map((i) => blocksByIndex[i]!).toList();
        _diagnostics.recordSuccess();
        yield _TurnComplete(contentBlocks, stopReason);
        return;
      } on NeuraGenerationCancelled {
        rethrow;
      } catch (error) {
        lastError = error;
        if (!emittedText && _canRetry(error) && attempt < _maxRetries) {
          _diagnostics.recordRetry();
          await cancel.delay(_retryDelay(attempt, const {}));
          continue;
        }
        _diagnostics.recordFailure(error);
        rethrow;
      } finally {
        client.close();
      }
    }

    final error = lastError ?? NeuraApiException('LLM request failed.');
    _diagnostics.recordFailure(error);
    throw error;
  }

  http.Request _buildStreamRequest(
    String systemPrompt,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) {
    final body = <String, dynamic>{
      'model': _model,
      'max_tokens': _maxTokens,
      'stream': true,
      'thinking': {'type': 'disabled'},
      'output_config': {'effort': 'low'},
      'system': _systemBlock(systemPrompt),
      if (tools.isNotEmpty) 'tools': tools,
      'messages': messages,
    };

    return http.Request('POST', Uri.parse(_endpoint))
      ..headers.addAll({
        'content-type': 'application/json',
        'x-api-key': _apiKey,
        'anthropic-version': '2023-06-01',
      })
      ..body = jsonEncode(body);
  }

  bool _canRetry(Object error) {
    if (error is NeuraApiException) {
      final status = error.statusCode;
      return status != null && _retryableStatuses.contains(status);
    }
    return error is http.ClientException || error is TimeoutException;
  }

  Duration _retryDelay(int attempt, Map<String, String> headers) {
    final retryAfter = int.tryParse(headers['retry-after'] ?? '');
    if (retryAfter != null && retryAfter >= 0) {
      final ms = retryAfter * 1000;
      return Duration(milliseconds: ms > _maxBackoffMs ? _maxBackoffMs : ms);
    }
    final rawMs = _initialBackoffMs * (1 << attempt);
    final ms = rawMs > _maxBackoffMs ? _maxBackoffMs : rawMs;
    return Duration(milliseconds: ms);
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
            NeuraToolCommand(
              NeuraChatPolicy.getMoodHistory,
              {'limit': limit},
            ),
          );
          if (!approved) {
            return 'The user did not approve sharing mood history.';
          }
          final entries = await MoodStore.instance.getAll();
          cancel.throwIfCancelled();
          final recent = entries.length > limit
              ? entries.sublist(entries.length - limit)
              : entries;
          if (recent.isEmpty) return 'No mood entries recorded yet.';
          return recent
              .map((e) =>
                  '${e.timestamp.toIso8601String()}: mood ${e.mood0to10}/10')
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
            NeuraToolCommand(
              NeuraChatPolicy.logMoodEntry,
              {'mood0to10': mood, 'note': note},
            ),
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
          final approved = await onToolCommand(NeuraToolCommand(
            NeuraChatPolicy.dispatchIntent,
            {'room': room},
          ));
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
          final approved = await onToolCommand(NeuraToolCommand(
            NeuraChatPolicy.setTone,
            {'tone': tone},
          ));
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

  /// One-shot, non-streaming completion for internally generated content.
  /// Uses the same bounded retry/backoff policy as chat, though it does not
  /// participate in user barge-in because there is no visible streamed reply.
  Future<String> completeOnce(
    String userPrompt, {
    required String agentId,
  }) async {
    _throwIfCloudBlocked();
    if (!isConfigured) {
      throw StateError('Configure the AI provider key in Settings.');
    }

    final syntheticRequest = [NeuraChatTurn(isUser: true, text: userPrompt)];
    final preBlocked = await _checkGuardrails(syntheticRequest);
    if (preBlocked != null) {
      throw NeuraGuardrailBlocked(preBlocked);
    }

    final systemPrompt =
        await NeuraPromptBuilder.instance.buildSystemMessage(agentId: agentId);

    final response = await _postWithRetry({
      'model': _model,
      'max_tokens': _maxTokens,
      'stream': false,
      'thinking': {'type': 'disabled'},
      'output_config': {'effort': 'low'},
      'system': _systemBlock(systemPrompt),
      'messages': syntheticRequest.map((t) => t.toJson()).toList(),
    });

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final blocks = decoded['content'] as List<dynamic>? ?? const [];
    final rawText = blocks
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text']?.toString() ?? '')
        .join();

    final syntheticReply = [NeuraChatTurn(isUser: true, text: rawText)];
    final postBlocked = await _checkGuardrails(syntheticReply);
    if (postBlocked != null) {
      throw NeuraGuardrailBlocked(postBlocked);
    }

    return rawText;
  }

  Future<http.Response> _postWithRetry(Map<String, dynamic> body) async {
    Object? lastError;
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        _throwIfCloudBlocked();
        _diagnostics.recordAttempt();
        final response = await http
            .post(
              Uri.parse(_endpoint),
              headers: {
                'content-type': 'application/json',
                'x-api-key': _apiKey,
                'anthropic-version': '2023-06-01',
              },
              body: jsonEncode(body),
            )
            .timeout(_requestTimeout);
        _throwIfCloudBlocked();
        if (response.statusCode == 200) {
          _diagnostics.recordSuccess();
          return response;
        }

        final error = NeuraApiException(
          '${response.statusCode}: ${response.body}',
          statusCode: response.statusCode,
        );
        lastError = error;
        if (_canRetry(error) && attempt < _maxRetries) {
          _diagnostics.recordRetry();
          await Future<void>.delayed(_retryDelay(attempt, response.headers));
          continue;
        }
        _diagnostics.recordFailure(error);
        throw error;
      } catch (error) {
        lastError = error;
        if (_canRetry(error) && attempt < _maxRetries) {
          _diagnostics.recordRetry();
          await Future<void>.delayed(_retryDelay(attempt, const {}));
          continue;
        }
        if (error is! NeuraApiException) {
          _diagnostics.recordFailure(error);
        }
        rethrow;
      }
    }

    final error = lastError ?? NeuraApiException('LLM request failed.');
    _diagnostics.recordFailure(error);
    throw error;
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

    final moodEntries = await MoodStore.instance.getAll();
    final recentEntries = moodEntries.length > 10
        ? moodEntries.sublist(moodEntries.length - 10)
        : moodEntries;
    final recentMoods = recentEntries
        .map(
          (e) => ((e.mood0to10 - 5) / 2.5).round().clamp(-2, 2).toInt(),
        )
        .toList(growable: false);
    final signal = DistressDetector().detect(
      recentMoods: recentMoods,
      appOpensLastHour: 0,
      lotsOfNegativeWords: false,
    );

    await NeuraAudienceService.instance.load();
    final isMinor =
        NeuraAudienceService.instance.currentAudience != NeuraAudience.adult;

    final snapshot = NeuraContextSnapshot(
      now: DateTime.now(),
      userInFocusMode:
          FocusController.instance.state.value.mode != FocusMode.off,
      isMinor: isMinor,
      distressScore: signal.active ? 0.9 : 0.1,
    );

    final proposal = NeuraProposal(
      type: ProposalType.prompt,
      id: 'chat_message',
      message: lastMessage,
      options: const ['send', 'no_thanks'],
    );

    final decision =
        Guardrails().evaluate(context: snapshot, proposal: proposal);
    if (decision.allow) return null;

    if (signal.active) {
      await WeeklySnapshotBridge.instance.logStormEvent(
        StormEvent(
          id: const Uuid().v4(),
          timestamp: DateTime.now(),
          intensity: 'medium',
          primaryFeeling: 'distressed',
          shortSummary: 'Distress detected during a chat conversation.',
          needNow: 'support',
          safetyRisk: true,
          meta: {'source': 'chat_guardrail', 'reasons': signal.reasons},
        ),
      );
    }

    var message = decision.safeAlternative?.message ?? decision.reason;
    final reasonLower = decision.reason.toLowerCase();
    if (reasonLower.contains('distress') || reasonLower.contains('support')) {
      message += '\n\nIf you need immediate help: '
          '${SupportResources.us['988']}. ${SupportResources.us['911']}.';
    }
    return message;
  }
}

abstract class _StreamEvent {}

class _TextDelta extends _StreamEvent {
  final String text;
  _TextDelta(this.text);
}

class _TurnComplete extends _StreamEvent {
  final List<Map<String, dynamic>> contentBlocks;
  final String stopReason;
  _TurnComplete(this.contentBlocks, this.stopReason);
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
