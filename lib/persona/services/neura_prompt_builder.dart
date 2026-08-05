import '../../core/memory/memory_graph_service.dart';
import '../../mood/services/mood_state_service.dart';
import '../agents/agent_persona_catalog.dart';
import '../models/neura_audience.dart';
import '../services/neura_persona_service.dart';
import '../services/neura_behavior_adapter.dart';
import '../models/neura_response_style.dart';

/// High-level helper to prepare Neura style + prompt data before calling your LLM.
class NeuraPromptBuilder {
  NeuraPromptBuilder._internal();
  static final NeuraPromptBuilder instance = NeuraPromptBuilder._internal();

  final _personaService = NeuraPersonaService.instance;
  final _moodState = MoodStateService.instance;
  final _adapter = NeuraBehaviorAdapter();

  /// Loads persona + mood and computes the current response style for
  /// [agentId] (see [AgentPersonaCatalog]).
  Future<NeuraResponseStyle> resolveStyle({
    String agentId = AgentPersonaCatalog.generalId,
    NeuraAudience? audience,
  }) async {
    await _personaService.load();
    await _moodState.load();

    final persona = _personaService.current;
    final mood = _moodState.currentMood;
    final agent = AgentPersonaCatalog.byId(agentId);

    return _adapter.computeStyle(
      persona: persona,
      mood: mood,
      agent: agent,
    );
  }

  /// Build a suggested system message string for your LLM client. Appends a
  /// short recap of recent memory-graph entries so Neura can recall things
  /// from past sessions - without this, every fresh chat screen starts from
  /// nothing since [_lines] there is only ever in-memory.
  Future<String> buildSystemMessage({
    String agentId = AgentPersonaCatalog.generalId,
    NeuraAudience? audience,
  }) async {
    final style = await resolveStyle(agentId: agentId, audience: audience);
    final memorySnippet = await _buildMemorySnippet();
    if (memorySnippet.isEmpty) return style.systemPromptSnippet;
    return '${style.systemPromptSnippet}\n\n$memorySnippet';
  }

  Future<String> _buildMemorySnippet() async {
    try {
      final nodes = await MemoryGraphService.I.recentNodes(limit: 8);
      final lines = nodes
          .map(_summarizeNode)
          .where((s) => s.isNotEmpty)
          .toList();
      if (lines.isEmpty) return '';
      return 'Relevant things you remember about this person from past '
          'conversations (most recent first) - use naturally, don\'t just '
          'recite this list:\n${lines.map((l) => '- $l').join('\n')}';
    } catch (_) {
      // Memory recall is a nice-to-have; never let it block a reply.
      return '';
    }
  }

  String _summarizeNode(Map<String, dynamic> node) {
    final type = node['type'] as String? ?? '';
    final payload = node['payload'] as Map<String, dynamic>? ?? {};
    String truncate(String s) => s.length > 160 ? '${s.substring(0, 160)}…' : s;

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
    return '';
  }
}
