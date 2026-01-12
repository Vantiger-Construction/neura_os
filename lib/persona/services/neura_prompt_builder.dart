import '../../mood/services/mood_state_service.dart';
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

  /// Loads persona + mood and computes the current response style.
  Future<NeuraResponseStyle> resolveStyle({
    String module = 'general',
  }) async {
    await _personaService.load();
    await _moodState.load();

    final persona = _personaService.current;
    final mood = _moodState.currentMood;

    return _adapter.computeStyle(
      persona: persona,
      mood: mood,
      module: module,
    );
  }

  /// Build a suggested system message string for your LLM client.
  Future<String> buildSystemMessage({
    String module = 'general',
  }) async {
    final style = await resolveStyle(module: module);
    return style.systemPromptSnippet;
  }
}
