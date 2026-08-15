import 'dart:async';
import 'dart:convert';

import '../../modules/core/app_log.dart';
import '../../persona/agents/agent_persona_catalog.dart';
import '../../services/neura_ai_service.dart';
import '../../startup/neura_prefs_cache.dart';
import 'memory_graph_service.dart';

/// A stored long-term "what Neura remembers about the user" profile and
/// when it was drafted.
class MemoryProfileState {
  final String profileText;
  final int generatedAtEpochMs;

  const MemoryProfileState({
    required this.profileText,
    required this.generatedAtEpochMs,
  });

  DateTime get generatedAt => DateTime.fromMillisecondsSinceEpoch(generatedAtEpochMs);

  Map<String, dynamic> toMap() => {
        'profileText': profileText,
        'generatedAtEpochMs': generatedAtEpochMs,
      };

  static MemoryProfileState? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final text = map['profileText']?.toString();
    final epoch = int.tryParse(map['generatedAtEpochMs']?.toString() ?? '');
    if (text == null || text.isEmpty || epoch == null) return null;
    return MemoryProfileState(profileText: text, generatedAtEpochMs: epoch);
  }
}

/// Summarizes older [MemoryGraphService] entries into a compact, persistent
/// "user profile" snippet, at most once every 7 days -- so
/// [NeuraPromptBuilder] can give the model a sense of who the user is
/// across weeks/months, not just [MemoryGraphService.recentNodes]'s last 8
/// entries.
///
/// Same "app-open-gated, no OS scheduler" pattern as
/// [WeeklySummaristService] -- see its doc comment for why.
///
/// The consolidated summary is deliberately NOT written back into the
/// memory graph itself (would mean summarizing summaries in a growing
/// feedback loop) -- it lives only in prefs, one snapshot at a time.
class MemoryConsolidationService {
  MemoryConsolidationService._();
  static final MemoryConsolidationService instance = MemoryConsolidationService._();

  static const _key = 'neura.memory_profile.v1';
  static const _staleAfter = Duration(days: 7);

  /// Below this many older nodes, skip consolidation entirely -- a profile
  /// drafted from a handful of entries is thin and not worth baking into
  /// every future system prompt.
  static const _minNodesToConsolidate = 20;

  Future<void>? _inFlight;
  int _dataGeneration = 0;

  Future<MemoryProfileState?> _load() async {
    try {
      final prefs = NeuraPrefsCache.prefs;
      final raw = prefs.getString(_key);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return MemoryProfileState.fromMap(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(MemoryProfileState state, int generation) async {
    if (generation != _dataGeneration) return;
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setString(_key, jsonEncode(state.toMap()));
    if (generation != _dataGeneration) await prefs.remove(_key);
  }

  Future<bool> isDue({DateTime? now}) async {
    final state = await _load();
    if (state == null) return true;
    return (now ?? DateTime.now()).isAfter(state.generatedAt.add(_staleAfter));
  }

  /// The current profile snippet, ready to prepend to a chat system prompt.
  /// Returns '' if nothing has been consolidated yet -- callers should
  /// treat that as "no profile available", not an error.
  Future<String> currentProfileSnippet() async {
    final state = await _load();
    if (state == null) return '';
    return "What you know about this person over time (not just this "
        "conversation) -- use naturally, don't recite it:\n${state.profileText}";
  }

  /// Call once per app launch. Concurrent callers collapse into one HTTP
  /// call via [_inFlight].
  Future<void> maybeConsolidateOnAppOpen() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final generation = _dataGeneration;
    final future = _consolidateIfDue(generation)
        .whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  Future<void> resetAfterDataWipe() async {
    _dataGeneration += 1;
    final inFlight = _inFlight;
    if (inFlight != null) {
      try {
        await inFlight.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        // Generation invalidation prevents a late response from re-persisting.
      }
    }
  }

  Future<void> _consolidateIfDue(int generation) async {
    if (!await isDue()) return;
    if (generation != _dataGeneration) return;
    if (!NeuraAiService.instance.isConfigured) return;

    try {
      final existing = await _load();
      if (generation != _dataGeneration) return;
      final cutoff = existing?.generatedAt ?? DateTime.now().subtract(const Duration(days: 3650));
      final nodes = await MemoryGraphService.I.nodesOlderThan(cutoff, limit: 200);
      if (generation != _dataGeneration) return;
      if (nodes.length < _minNodesToConsolidate) return;

      final excerpts = nodes.map(_summarizeNode).where((s) => s.isNotEmpty).toList();
      if (excerpts.length < _minNodesToConsolidate) return;

      final prompt = 'Conversation excerpts, oldest first:\n'
          '${excerpts.map((s) => '- $s').join('\n')}\n\n'
          'Summarize what a companion should remember about this person going forward.';

      if (generation != _dataGeneration) return;
      final text = await NeuraAiService.instance.completeOnce(
        prompt,
        agentId: AgentPersonaCatalog.memoryConsolidator.id,
      );

      if (generation != _dataGeneration) return;
      await _save(MemoryProfileState(
        profileText: text,
        generatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      ), generation);
    } catch (e, st) {
      if (generation != _dataGeneration) return;
      // Network failure, guardrail block, or missing key -- stay "due",
      // retry next app-open. Chat just proceeds without a profile snippet.
      await AppLog.instance.caught('memory_consolidation_failed', e, st);
    }
  }

  String _summarizeNode(Map<String, dynamic> node) {
    final type = node['type'] as String? ?? '';
    final payload = node['payload'] as Map<String, dynamic>? ?? {};
    String truncate(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

    if (type == 'ACTION:CHAT_MESSAGE') {
      return 'They said: "${truncate(payload['text']?.toString() ?? '')}"';
    }
    if (type == 'SUGGESTION:CHAT_REPLY') {
      return 'You replied: "${truncate(payload['text']?.toString() ?? '')}"';
    }
    if (type == 'ACTION:THERAPY_REFLECTION') {
      final title = payload['promptTitle']?.toString() ?? 'a reflection';
      return 'They reflected on "$title": ${truncate(payload['text']?.toString() ?? '')}';
    }
    if (type == 'ACTION:MIRROR_CHECKIN') {
      final mood = payload['mood']?.toString() ?? '';
      final reflection = payload['reflection']?.toString();
      return reflection == null || reflection.isEmpty
          ? 'They checked in feeling $mood.'
          : 'They checked in feeling $mood: ${truncate(reflection)}';
    }
    return '';
  }
}
