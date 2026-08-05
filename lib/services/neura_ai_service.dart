import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../after_storm/models/storm_event.dart';
import '../care/services/care_mode_bridge.dart';
import '../guardrails/guardrails.dart';
import '../guardrails/guardrails_types.dart';
import '../guardrails/support_resources.dart';
import '../modules/mood/mood_store.dart';
import '../persona/agents/agent_persona_catalog.dart';
import '../persona/models/neura_audience.dart';
import '../persona/services/neura_audience_service.dart';
import '../persona/services/neura_prompt_builder.dart';
import '../relationships/services/distress_detector.dart';
import '../src/modules/focus/focus_controller.dart';
import '../src/modules/focus/focus_mode.dart';

/// One turn in the conversation, in the shape the Messages API expects.
class NeuraChatTurn {
  final bool isUser;
  final String text;
  const NeuraChatTurn({required this.isUser, required this.text});

  Map<String, dynamic> toJson() => {
        'role': isUser ? 'user' : 'assistant',
        'content': text,
      };
}

/// Raw HTTP client for the Anthropic Messages API — there is no official
/// Dart SDK, so this talks to the streaming endpoint directly (SSE, parsed
/// by hand). See https://platform.claude.com/docs for the wire format.
///
/// The API key is baked into this beta build via --dart-define at build
/// time (ANTHROPIC_API_KEY), not committed to source control.
class NeuraAiService {
  NeuraAiService._();
  static final NeuraAiService instance = NeuraAiService._();

  static const _apiKey = String.fromEnvironment('ANTHROPIC_API_KEY');
  static const _model = 'claude-opus-4-8';
  static const _maxTokens = 1024;
  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  bool get isConfigured => _apiKey.isNotEmpty;

  /// Streams incremental text deltas for a reply to [history] (last entry is
  /// the new user message), answering as [agentId] (see
  /// [AgentPersonaCatalog]). Applies Neura's persona/mood/safety system
  /// prompt (see NeuraPromptBuilder) on every call.
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

    final request = http.Request('POST', Uri.parse(_endpoint))
      ..headers.addAll({
        'content-type': 'application/json',
        'x-api-key': _apiKey,
        'anthropic-version': '2023-06-01',
      })
      ..body = jsonEncode({
        'model': _model,
        'max_tokens': _maxTokens,
        'stream': true,
        'system': systemPrompt,
        'messages': history.map((t) => t.toJson()).toList(),
      });

    final streamedResponse = await http.Client().send(request);
    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      throw NeuraApiException('${streamedResponse.statusCode}: $body');
    }

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
        if (event['type'] == 'content_block_delta') {
          final delta = event['delta'] as Map<String, dynamic>?;
          if (delta?['type'] == 'text_delta') {
            yield delta!['text'] as String;
          }
        } else if (event['type'] == 'error') {
          final error = event['error'] as Map<String, dynamic>?;
          throw NeuraApiException(error?['message']?.toString() ?? 'Unknown API error');
        }
      }
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

    final response = await http.post(
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
        'system': systemPrompt,
        'messages': syntheticRequest.map((t) => t.toJson()).toList(),
      }),
    );

    if (response.statusCode != 200) {
      throw NeuraApiException('${response.statusCode}: ${response.body}');
    }

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

class NeuraApiException implements Exception {
  final String message;
  NeuraApiException(this.message);
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
