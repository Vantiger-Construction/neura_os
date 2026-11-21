import '../../teaching/neura_teaching_preferences.dart';
import '../models/agent_persona.dart';
import '../models/persona_profile.dart';
import '../models/neura_response_style.dart';
import '../../mood/services/mood_theme_service.dart';

/// Converts PersonaProfile + current mood into concrete behavior knobs
/// Neura can use when answering.
class NeuraBehaviorAdapter {
  NeuraResponseStyle computeStyle({
    required PersonaProfile persona,
    required String mood,
    required AgentPersona agent,
    NeuraAnswerDetail? answerDetail,
  }) {
    final moodTheme = MoodThemeService.instance.themeFor(mood);
    final difficulty = moodTheme.difficulty;

    // Tone label
    String toneLabel;
    if (persona.warmth >= 0.7 && persona.directness <= 0.6) {
      toneLabel = 'soft';
    } else if (persona.directness >= 0.7) {
      toneLabel = 'direct';
    } else {
      toneLabel = 'balanced';
    }

    // Joke frequency mainly from humor, but toned down on crisis-type moods.
    double jokeFrequency = persona.humor;
    final lowerMood = mood.toLowerCase();
    if (lowerMood == 'sad' ||
        lowerMood == 'anxious' ||
        lowerMood == 'scared' ||
        lowerMood == 'tired') {
      jokeFrequency *= 0.5;
    }

    // Depth: persona depth, but if user is exhausted, tilt a bit toward simpler.
    double depthLevel = answerDetail?.depth ?? persona.depth;
    if (lowerMood == 'tired' || lowerMood == 'overwhelmed') {
      depthLevel = (depthLevel * 0.7).clamp(0.0, 1.0);
    }

    // Energy: from persona, but also from mood.
    double energyLevel = persona.energy;
    if (lowerMood == 'tired' || lowerMood == 'sad') {
      energyLevel = (energyLevel * 0.6).clamp(0.0, 1.0);
    } else if (lowerMood == 'happy' || lowerMood == 'excited') {
      energyLevel = (energyLevel * 0.4 + 0.6).clamp(0.0, 1.0);
    }

    final useDirectLanguage = persona.directness >= 0.65;

    final systemPromptSnippet = _buildPromptSnippet(
      persona.copyWith(
        humor: jokeFrequency,
        depth: depthLevel,
        energy: energyLevel,
      ),
      mood,
      difficulty,
      toneLabel,
      agent,
      answerDetail,
    );

    return NeuraResponseStyle(
      toneLabel: toneLabel,
      jokeFrequency: jokeFrequency,
      depthLevel: depthLevel,
      energyLevel: energyLevel,
      useDirectLanguage: useDirectLanguage,
      difficulty: difficulty,
      systemPromptSnippet: systemPromptSnippet,
      explicitAnswerDetail: answerDetail,
    );
  }

  String _buildPromptSnippet(
    PersonaProfile persona,
    String mood,
    String difficulty,
    String toneLabel,
    AgentPersona agent,
    NeuraAnswerDetail? answerDetail,
  ) {
    final moodStr = mood.isEmpty ? 'neutral' : mood.toLowerCase();

    final warmText = persona.warmth >= 0.7
        ? 'Sound very caring and emotionally present.'
        : (persona.warmth <= 0.3
            ? 'Be more factual, less emotional.'
            : 'Be kind, not sentimental.');

    final directText = persona.directness >= 0.7
        ? 'Be direct and honest, never cruel.'
        : (persona.directness <= 0.3
            ? 'Deliver hard truths very gently.'
            : 'Be honest but soft.');

    final humorText = persona.humor >= 0.7
        ? 'Use playful humor, never about real pain.'
        : (persona.humor <= 0.3
            ? 'Avoid jokes.'
            : 'Light humor only when it feels safe.');

    final defaultDepthText = persona.depth >= 0.7
        ? 'Reflect on patterns and values, not just tips.'
        : (persona.depth <= 0.3
            ? 'Keep answers short and practical.'
            : 'Balance practical tips and reflection.');

    // This bounded setting changes delivery, not identity, safety or authority.
    // The current request always overrides this user-selected default.
    final depthText = switch (answerDetail) {
      NeuraAnswerDetail.brief =>
        'Default to brief answers. Follow the user\'s requested detail for this reply.',
      NeuraAnswerDetail.balanced =>
        'Default to concise answers. Follow the user\'s requested detail for this reply.',
      NeuraAnswerDetail.detailed =>
        'Default to fuller answers with examples. Follow the user\'s requested detail for this reply.',
      null => defaultDepthText,
    };

    final energyText = persona.energy >= 0.7
        ? 'Bring high energy.'
        : (persona.energy <= 0.3
            ? 'Speak calmly and softly.'
            : 'Keep a steady and grounded energy.');

    String difficultyText;
    switch (difficulty) {
      case 'gentle':
        difficultyText = 'Put emotional safety first; suggest tiny steps.';
        break;
      case 'challenge':
        difficultyText = 'Gently challenge them to stretch if safe.';
        break;
      default:
        difficultyText = 'Balance challenge and comfort.';
    }

    final roleBullets = agent.roleInstructions.map((r) => '- $r').join('\n');

    return '''
${agent.identityPrompt} Last check-in: "$moodStr" mood. How they sound right now matters more.
Tone: $toneLabel. Shape how you sound with these; never mention them:
- $warmText
- $directText
- $humorText
- $depthText
- $energyText
- $difficultyText
${roleBullets.isEmpty ? '' : '\n$roleBullets'}
''';
  }
}
