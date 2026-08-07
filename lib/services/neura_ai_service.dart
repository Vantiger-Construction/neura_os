import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../after_storm/models/storm_event.dart';
import '../care/services/care_mode_bridge.dart';
import '../guardrails/guardrails.dart';
import '../guardrails/guardrails_types.dart';
import '../guardrails/support_resources.dart';
import '../modules/mood/mood_models.dart';
import '../modules/mood/mood_store.dart';
import '../persona/agents/agent_persona_catalog.dart';
import '../persona/models/neura_audience.dart';
import '../persona/services/neura_audience_service.dart';
import '../persona/services/neura_prompt_builder.dart';
import '../relationships/services/distress_detector.dart';
import '../src/modules/focus/focus_controller.dart';
import '../src/modules/focus/focus_mode.dart';

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

/// Raw HTTP client for the Anthropic Messages API — there is no official
/// Dart SDK, so this talks to the streaming endpoint directly (SSE, parsed
/// by hand). See https://platform.claude.com/docs for the wire format.
///
/// The API key is baked into this beta build via --dart-define at build
/// time (ANTHROPIC_API_KEY), not committed to source control.
///
/// Model: Claude Sonnet 5. Supports tool use (Neura can read/log the user's
/// mood, and search the web, via [_tools]), vision (photos attached to a
/// chat turn), prompt caching (system prompt + a rolling per-turn
/// breakpoint), and retries transient failures (429/5xx/network) with
/// exponential backoff before any content has been streamed to the caller.
class NeuraAiService {
  NeuraAiService._();
  static final NeuraAiService instance = NeuraAiService._();

  static const _apiKey = String.fromEnvironment('ANTHROPIC_API_KEY');
  static const _model = 'claude-sonnet-5';
  static const _maxTokens = 2048;
  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  /// Safety cap on tool-use / server-tool-loop round trips within a single
  /// reply, so a misbehaving loop can't spin forever.
  static const _maxToolRounds = 4;

  /// Retries for a request that hasn't streamed any content back yet (a
  /// non-200 status, or a transport failure before the connection opened).
  /// Once we've started forwarding text deltas to the caller, a later
  /// failure is surfaced as-is rather than retried, since re-sending would
  /// duplicate output already shown in the chat.
  static const _maxRetries = 3;

  static const _tools = [
    {
      'name': 'get_mood_history',
      'description':
          "Get the user's recent mood check-in history (timestamp, 0-10 "
          'mood score, and note). Call this when the user asks about their '
          'mood history, trends, or wants a summary of how they have been '
          'feeling recently.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description':
                'Max number of most recent entries to return. Defaults to 10.',
          },
        },
        'required': <String>[],
      },
    },
    {
      'name': 'log_mood_entry',
      'description':
          'Record a new mood check-in for the user. Call this when the user '
          "explicitly describes today's mood/feeling as a check-in they want "
          "saved (e.g. \"I'm about a 7 today\", \"log that I'm anxious\") — "
          'not for every passing mention of an emotion in conversation.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'mood0to10': {
            'type': 'integer',
            'description': 'Mood rating from 0 (worst) to 10 (best).',
          },
          'note': {
            'type': 'string',
            'description': 'Short note describing the mood or context.',
          },
        },
        'required': ['mood0to10'],
      },
    },
    // Server-side tool: Anthropic runs the search and returns results with
    // citations, no client execution needed. Capped at 3 uses/turn so an
    // open-ended research tangent can't run away with cost.
    {
      'type': 'web_search_20260209',
      'name': 'web_search',
      'max_uses': 3,
    },
  ];

  bool get isConfigured => _apiKey.isNotEmpty;

  static List<Map<String, dynamic>> _systemBlock(String systemPrompt) => [
        {
          'type': 'text',
          'text': systemPrompt,
          'cache_control': {'type': 'ephemeral'},
        },
      ];

  /// Returns a copy of [messages] with a cache breakpoint on the last
  /// content block of the last message. As a conversation grows, every
  /// earlier turn up to this point is then served from cache on the next
  /// request instead of being repriced in full -- see
  /// shared/prompt-caching.md "Multi-turn conversations".
  static List<Map<String, dynamic>> _withTrailingCacheBreakpoint(
    List<Map<String, dynamic>> messages,
  ) {
    if (messages.isEmpty) return messages;
    final copy = messages.map((m) => Map<String, dynamic>.from(m)).toList();
    final last = copy.last;
    final content = last['content'];

    List<Map<String, dynamic>> blocks;
    if (content is String) {
      blocks = [
        {'type': 'text', 'text': content}
      ];
    } else if (content is List) {
      blocks = content
          .map((b) => b is Map<String, dynamic>
              ? Map<String, dynamic>.from(b)
              : <String, dynamic>{})
          .toList();
    } else {
      return copy;
    }
    if (blocks.isEmpty) return copy;

    blocks[blocks.length - 1] = {
      ...blocks.last,
      'cache_control': {'type': 'ephemeral'},
    };
    last['content'] = blocks;
    return copy;
  }

  /// Streams incremental text deltas for a reply to [history] (last entry is
  /// the new user message), answering as [agentId] (see
  /// [AgentPersonaCatalog]). Applies Neura's persona/mood/safety system
  /// prompt (see NeuraPromptBuilder) on every call. Transparently runs any
  /// client-side tool calls the model makes (see [_tools]) and resumes a
  /// server-tool loop that hit its iteration cap (`pause_turn`), continuing
  /// to stream the follow-up reply either way.
  Stream<String> streamReply(
    List<NeuraChatTurn> history, {
    String agentId = AgentPersonaCatalog.generalId,
  }) async* {
    if (!isConfigured) {
      throw StateError('ANTHROPIC_API_KEY was not set at build time.');
    }

    final blocked = await _checkGuardrails(history);
    if (blocked != null) {
      yield blocked;
      return;
    }

    final systemPrompt =
        await NeuraPromptBuilder.instance.buildSystemMessage(agentId: agentId);

    final messages = history.map((t) => t.toJson()).toList();

    var rounds = 0;
    while (true) {
      List<Map<String, dynamic>>? finishedBlocks;
      var stopReason = 'end_turn';

      await for (final event in _streamOneTurn(systemPrompt, messages)) {
        if (event is _TextDelta) {
          yield event.text;
        } else if (event is _TurnComplete) {
          finishedBlocks = event.contentBlocks;
          stopReason = event.stopReason;
        }
      }

      final blocks = finishedBlocks;
      if (blocks == null) break;

      if (stopReason == 'pause_turn') {
        // The server-side tool loop (e.g. web_search) hit its iteration
        // cap mid-turn. Re-send as-is to resume -- no synthetic "Continue"
        // message; the API detects the trailing server_tool_use block.
        if (++rounds > _maxToolRounds) break;
        messages.add({'role': 'assistant', 'content': blocks});
        continue;
      }

      if (stopReason != 'tool_use' || blocks.isEmpty) break;
      if (++rounds > _maxToolRounds) break;

      messages.add({'role': 'assistant', 'content': blocks});

      final toolResults = <Map<String, dynamic>>[];
      for (final block in blocks) {
        if (block['type'] != 'tool_use') continue;
        final resultText = await _executeTool(
          block['name'] as String,
          (block['input'] as Map<String, dynamic>?) ?? const {},
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
  }

  /// Runs one streamed turn against the Messages API and yields text deltas
  /// as they arrive, finishing with a [_TurnComplete] carrying every content
  /// block (needed to replay the assistant turn verbatim on a follow-up
  /// tool result or a `pause_turn` resume) and the response's stop reason.
  Stream<_StreamEvent> _streamOneTurn(
    String systemPrompt,
    List<Map<String, dynamic>> messages,
  ) async* {
    final streamedResponse = await _sendWithRetry(
      () => http.Request('POST', Uri.parse(_endpoint))
        ..headers.addAll({
          'content-type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        })
        ..body = jsonEncode({
          'model': _model,
          'max_tokens': _maxTokens,
          'stream': true,
          // Chat replies favor low latency over deliberation; tool
          // selection doesn't need extended reasoning for this tool set.
          'thinking': {'type': 'disabled'},
          'output_config': {'effort': 'low'},
          'system': _systemBlock(systemPrompt),
          'tools': _tools,
          'messages': _withTrailingCacheBreakpoint(messages),
        }),
    );

    final blocksByIndex = <int, Map<String, dynamic>>{};
    final toolInputBuffers = <int, StringBuffer>{};
    var stopReason = 'end_turn';

    var buffer = '';
    await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
      buffer += chunk;
      final lines = buffer.split('\n');
      // Keep the last (possibly incomplete) line in the buffer.
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
            // server_tool_use (e.g. web_search) streams its input the same
            // way tool_use does -- buffer it so it can be finalized below.
            if (block['type'] == 'tool_use' ||
                block['type'] == 'server_tool_use') {
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
                  // Malformed tool input JSON — leave it empty; the tool
                  // executor below will simply see no arguments.
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
                error?['message']?.toString() ?? 'Unknown API error');
        }
      }
    }

    final orderedIndices = blocksByIndex.keys.toList()..sort();
    final contentBlocks =
        orderedIndices.map((i) => blocksByIndex[i]!).toList();
    yield _TurnComplete(contentBlocks, stopReason);
  }

  /// Executes a tool call by name, returning the text to send back as the
  /// tool_result content. Never throws — a failure becomes an error string
  /// the model can react to instead of breaking the conversation.
  Future<String> _executeTool(String name, Map<String, dynamic> input) async {
    try {
      switch (name) {
        case 'get_mood_history':
          final limit = (input['limit'] as num?)?.toInt() ?? 10;
          final entries = await MoodStore.instance.getAll();
          final recent =
              entries.length > limit ? entries.sublist(entries.length - limit) : entries;
          if (recent.isEmpty) return 'No mood entries recorded yet.';
          return recent
              .map((e) =>
                  '${e.timestamp.toIso8601String()}: mood ${e.mood0to10}/10'
                  '${e.note.isEmpty ? '' : ' — ${e.note}'}')
              .join('\n');

        case 'log_mood_entry':
          final moodRaw = input['mood0to10'];
          if (moodRaw is! num) {
            return 'Tool error: mood0to10 is required.';
          }
          final mood = moodRaw.round().clamp(0, 10);
          final note = (input['note'] as String?) ?? '';
          await MoodStore.instance.add(
            MoodEntry(timestamp: DateTime.now(), mood0to10: mood, note: note),
          );
          return 'Logged mood $mood/10${note.isEmpty ? '' : ' — $note'}.';

        default:
          return 'Unknown tool: $name';
      }
    } catch (e) {
      return 'Tool error: $e';
    }
  }

  /// One-shot, non-streaming completion for content generated internally
  /// (not a chat reply) -- e.g. the weekly summarist. Goes through the same
  /// guardrail + prompt-builder pipeline as [streamReply], applied twice:
  /// once to the outgoing [userPrompt] (skips generation entirely if the
  /// user's recent mood history alone trips a hard block) and once to the
  /// model's own output (catches the rare case the drafted text itself
  /// trips the same check). Unlike [streamReply] -- which returns the
  /// guardrail's safe-alternative message inline, correct for interactive
  /// chat -- a block here throws [NeuraGuardrailBlocked] so the caller can
  /// simply skip showing anything, since there's no chat UI to show a
  /// safe-alternative message in.
  ///
  /// [agentId] is required (no "general" default): a one-shot
  /// content-generation call should always be explicit about which persona
  /// is drafting.
  Future<String> completeOnce(
    String userPrompt, {
    required String agentId,
  }) async {
    if (!isConfigured) {
      throw StateError('ANTHROPIC_API_KEY was not set at build time.');
    }

    final syntheticRequest = [NeuraChatTurn(isUser: true, text: userPrompt)];
    final preBlocked = await _checkGuardrails(syntheticRequest);
    if (preBlocked != null) {
      throw NeuraGuardrailBlocked(preBlocked);
    }

    final systemPrompt =
        await NeuraPromptBuilder.instance.buildSystemMessage(agentId: agentId);

    final response = await _postWithRetry(
      Uri.parse(_endpoint),
      headers: {
        'content-type': 'application/json',
        'x-api-key': _apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': _model,
        'max_tokens': _maxTokens,
        'stream': false,
        'thinking': {'type': 'disabled'},
        'output_config': {'effort': 'low'},
        'system': _systemBlock(systemPrompt),
        'messages': syntheticRequest.map((t) => t.toJson()).toList(),
      }),
    );

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

  static bool _isRetryableStatus(int code) =>
      code == 429 || code == 500 || code == 502 || code == 503 || code == 529;

  static Duration _backoffDelay(int attempt, {String? retryAfterHeader}) {
    final headerSeconds =
        retryAfterHeader != null ? int.tryParse(retryAfterHeader) : null;
    if (headerSeconds != null) return Duration(seconds: headerSeconds);
    return Duration(milliseconds: 500 * (1 << attempt)); // 500ms, 1s, 2s, 4s
  }

  /// Sends a streaming request, retrying a non-200 response or a transport
  /// failure with exponential backoff (honoring `retry-after` when present).
  /// [buildRequest] must build a fresh [http.Request] each call -- a
  /// `http.Request` can only be sent once.
  Future<http.StreamedResponse> _sendWithRetry(
    http.Request Function() buildRequest,
  ) async {
    for (var attempt = 0;; attempt++) {
      http.StreamedResponse response;
      try {
        response = await http.Client().send(buildRequest());
      } on http.ClientException {
        if (attempt >= _maxRetries) rethrow;
        await Future.delayed(_backoffDelay(attempt));
        continue;
      }

      if (response.statusCode == 200) return response;
      if (!_isRetryableStatus(response.statusCode) || attempt >= _maxRetries) {
        final body = await response.stream.bytesToString();
        throw NeuraApiException(
          '${response.statusCode}: $body',
          statusCode: response.statusCode,
        );
      }
      await response.stream.drain<void>();
      await Future.delayed(_backoffDelay(
        attempt,
        retryAfterHeader: response.headers['retry-after'],
      ));
    }
  }

  /// Non-streaming counterpart of [_sendWithRetry] for [completeOnce].
  Future<http.Response> _postWithRetry(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) async {
    for (var attempt = 0;; attempt++) {
      http.Response response;
      try {
        response = await http.post(uri, headers: headers, body: body);
      } on http.ClientException {
        if (attempt >= _maxRetries) rethrow;
        await Future.delayed(_backoffDelay(attempt));
        continue;
      }

      if (response.statusCode == 200) return response;
      if (!_isRetryableStatus(response.statusCode) || attempt >= _maxRetries) {
        throw NeuraApiException(
          '${response.statusCode}: ${response.body}',
          statusCode: response.statusCode,
        );
      }
      await Future.delayed(_backoffDelay(
        attempt,
        retryAfterHeader: response.headers['retry-after'],
      ));
    }
  }

  /// Runs the outgoing user message through Guardrails before it reaches the
  /// LLM. Returns a safe-alternative message to show instead if blocked, or
  /// null to proceed normally -- true for the overwhelming majority of
  /// messages; only real distress or exclusive/manipulative language trips
  /// the hard-block branches in guardrails_rules.dart.
  Future<String?> _checkGuardrails(List<NeuraChatTurn> history) async {
    if (history.isEmpty) return null;
    final lastMessage = history.last.text;

    final moodEntries = await MoodStore.instance.getAll();
    final recentEntries = moodEntries.length > 10
        ? moodEntries.sublist(moodEntries.length - 10)
        : moodEntries;
    final recentMoods = recentEntries
        .map((e) => ((e.mood0to10 - 5) / 2.5).round().clamp(-2, 2))
        .toList();
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
      userInFocusMode: FocusController.instance.state.value.mode != FocusMode.off,
      isMinor: isMinor,
      distressScore: signal.active ? 0.9 : 0.1,
    );

    final proposal = NeuraProposal(
      type: ProposalType.prompt,
      id: 'chat_message',
      message: lastMessage,
      options: const ['send', 'no_thanks'],
    );

    final decision = Guardrails().evaluate(context: snapshot, proposal: proposal);
    if (decision.allow) return null;

    if (signal.active) {
      await CareModeBridge.instance.logStormEvent(
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

/// Internal event type streamed out of [NeuraAiService._streamOneTurn].
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
  /// The HTTP status code, when this came from a non-200 response (after
  /// retries were exhausted or the failure wasn't retryable). Null for
  /// transport-level failures and API-reported SSE `error` events.
  final int? statusCode;
  NeuraApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// Thrown by [NeuraAiService.completeOnce] when Guardrails blocks either the
/// outgoing prompt or the model's own drafted output. Carries the
/// guardrail's message for logging/debugging, but callers of `completeOnce`
/// are expected to treat this like a network failure and show nothing.
class NeuraGuardrailBlocked implements Exception {
  final String guardrailMessage;
  NeuraGuardrailBlocked(this.guardrailMessage);
  @override
  String toString() => 'NeuraGuardrailBlocked: $guardrailMessage';
}
