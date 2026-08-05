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

  /// Build a suggested system message string for your LLM client.
  Future<String> buildSystemMessage({
    String agentId = AgentPersonaCatalog.generalId,
    NeuraAudience? audience,
  }) async {
    final style = await resolveStyle(agentId: agentId, audience: audience);
    return style.systemPromptSnippet;
  }
}
