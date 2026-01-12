import '../../persona/models/neura_audience.dart';
import '../../persona/services/neura_audience_service.dart';
import '../../persona/services/neura_prompt_builder.dart';
import '../../persona/services/neura_persona_service.dart';
import '../../mood/services/mood_state_service.dart';
import '../models/neura_chat_request.dart';

/// Single entry point for preparing Neura chat requests.
/// This glues together persona, mood, audience, and module hints.
class NeuraConversationEngine {
  NeuraConversationEngine._internal();
  static final NeuraConversationEngine instance =
      NeuraConversationEngine._internal();

  final _audienceService = NeuraAudienceService.instance;
  final _promptBuilder = NeuraPromptBuilder.instance;
  final _personaService = NeuraPersonaService.instance;
  final _moodState = MoodStateService.instance;

  /// Prepare a chat request with all context baked in.
  ///
  /// - [userMessage]: what the user typed
  /// - [module]: where in the app they are (journal, care_mode, dream_show, etc.)
  /// - [audienceOverride]: optional; if null, use stored audience preference.
  Future<NeuraChatRequest> prepare({
    required String userMessage,
    String module = 'general',
    NeuraAudience? audienceOverride,
  }) async {
    await _audienceService.load();
    await _personaService.load();
    await _moodState.load();

    final audience = audienceOverride ?? _audienceService.currentAudience;

    final style = await _promptBuilder.resolveStyle(
      module: module,
      audience: audience,
    );

    final systemMessage = await _promptBuilder.buildSystemMessage(
      module: module,
      audience: audience,
    );

    return NeuraChatRequest(
      systemMessage: systemMessage,
      userMessage: userMessage,
      metadata: {
        'audience': audience.label,
        'tone': style.toneLabel,
        'difficulty': style.difficulty,
        'jokeFrequency': style.jokeFrequency,
        'depthLevel': style.depthLevel,
        'energyLevel': style.energyLevel,
      },
    );
  }
}
