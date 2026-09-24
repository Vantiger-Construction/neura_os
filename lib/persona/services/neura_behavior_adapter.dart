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
    double depthLevel = persona.depth;
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

    final systemPromptSnippet =
        _buildPromptSnippet(persona, mood, difficulty, toneLabel, agent);

    return NeuraResponseStyle(
      toneLabel: toneLabel,
      jokeFrequency: jokeFrequency,
      depthLevel: depthLevel,
      energyLevel: energyLevel,
      useDirectLanguage: useDirectLanguage,
      difficulty: difficulty,
      systemPromptSnippet: systemPromptSnippet,
    );
  }

  String _buildPromptSnippet(
    PersonaProfile persona,
    String mood,
    String difficulty,
    String toneLabel,
    AgentPersona agent,
  ) {
    final moodStr = mood.isEmpty ? 'neutral' : mood.toLowerCase();

    final warmText = persona.warmth >= 0.7
        ? 'Sound very caring and emotionally present.'
        : (persona.warmth <= 0.3
            ? 'Stay more factual and less emotionally involved.'
            : 'Be kind but not overly sentimental.');

    final directText = persona.directness >= 0.7
        ? 'Be very direct and honest, avoid sugar-coating, but avoid cruelty.'
        : (persona.directness <= 0.3
            ? 'Be very gentle and indirect when delivering hard truths.'
            : 'Be honest but keep your language soft.');

    final humorText = persona.humor >= 0.7
        ? 'Use playful humor when appropriate, but never minimize serious pain.'
        : (persona.humor <= 0.3
            ? 'Avoid jokes and keep a serious tone.'
            : 'Use light, occasional humor only when it feels safe.');

    final depthText = persona.depth >= 0.7
        ? 'Offer deeper reflections about patterns and values, not just surface tips.'
        : (persona.depth <= 0.3
            ? 'Keep your answers short, practical, and focused on immediate next steps.'
            : 'Balance practical suggestions with some reflective insight.');

    final energyText = persona.energy >= 0.7
        ? 'Bring high energy and motivational language.'
        : (persona.energy <= 0.3
            ? 'Speak slowly, calmly, and softly.'
            : 'Keep a steady and grounded energy.');

    String difficultyText;
    switch (difficulty) {
      case 'gentle':
        difficultyText =
            'Prioritize emotional safety over challenge. Suggest tiny, low-pressure steps.';
        break;
      case 'challenge':
        difficultyText =
            'Gently challenge the user to stretch themselves if it seems safe.';
        break;
      default:
        difficultyText = 'Keep a balanced level of challenge and comfort.';
    }

    final roleBullets = agent.roleInstructions.map((r) => '- $r').join('\n');

    return '''
${agent.identityPrompt} The user is currently in a "$moodStr" mood.
Overall tone: $toneLabel. Let the following shape how you sound; never mention these settings.

Behavior rules:
- $warmText
- $directText
- $humorText
- $depthText
- $energyText
- $difficultyText
${roleBullets.isEmpty ? '' : '\n$roleBullets'}

General rules:
- Never give harmful advice.
- Encourage professional help when there are signs of crisis or self-harm.
- Speak like a supportive, emotionally intelligent friend, and answer questions directly.
''';
  }
}
