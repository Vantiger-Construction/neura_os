import 'joy_types.dart';

class JoyMoments {
  static JoyMoment fallback() => const JoyMoment(
        id: 'fallback_calm_breath',
        title: 'One Minute Reset',
        description:
            'A tiny breath reset. No pressure. Just oxygen doing its thing.',
        type: JoyMomentType.breathingGame,
        minutes: 1,
        payload: {'pattern': '4-4-6'},
      );

  static List<JoyMoment> poolFor(
    NeuraMood mood, {
    NeuraIntent? intent,
    JoyPreferenceProfile? prefs,
  }) {
    prefs ??= const JoyPreferenceProfile();

    final base = <JoyMoment>[
      if (prefs.likesGames)
        const JoyMoment(
          id: 'gratitude_dice',
          title: 'Gratitude Dice',
          description: 'Roll a prompt. Answer in one sentence. Done.',
          type: JoyMomentType.gratitudeDice,
          minutes: 2,
          payload: {'faces': 6},
        ),
      if (prefs.likesCreativity)
        const JoyMoment(
          id: 'creative_micro_poem',
          title: 'Micro-Poem',
          description: 'Write 3 lines about whatever is in front of you.',
          type: JoyMomentType.creativePrompt,
          minutes: 3,
          payload: {'format': '3_lines'},
        ),
      if (prefs.likesHumor)
        const JoyMoment(
          id: 'gentle_joke_01',
          title: 'Tiny Joke',
          description: 'A harmless giggle to soften the edges.',
          type: JoyMomentType.gentleJoke,
          minutes: 1,
          payload: {
            'joke':
                'Why did the neuron bring a suitcase? It wanted to make more connections.'
          },
        ),
      const JoyMoment(
        id: 'breath_box',
        title: 'Box Breathing',
        description: 'Inhale. Hold. Exhale. Hold. Repeat.',
        type: JoyMomentType.breathingGame,
        minutes: 2,
        payload: {'pattern': '4-4-4-4'},
      ),
      const JoyMoment(
        id: 'tiny_quest_clean',
        title: 'Tiny Quest',
        description:
            'Pick one micro-action: water, stretch, or tidy one small thing.',
        type: JoyMomentType.tinyQuest,
        minutes: 3,
        payload: {
          'options': ['drink_water', 'stretch_30s', 'tidy_one_item']
        },
      ),
    ];

    switch (mood) {
      case NeuraMood.stressed:
        return base.where((m) => m.type != JoyMomentType.gentleJoke).toList()
          ..insert(
              0,
              const JoyMoment(
                id: 'breath_478',
                title: '4-7-8 Breathing',
                description: 'A calmer nervous system in 2 minutes.',
                type: JoyMomentType.breathingGame,
                minutes: 2,
                payload: {'pattern': '4-7-8'},
              ));
      case NeuraMood.sad:
        return [
          const JoyMoment(
            id: 'soft_connection',
            title: 'Soft Connection',
            description: 'Text one person: “Thinking of you.” That’s it.',
            type: JoyMomentType.tinyQuest,
            minutes: 2,
            payload: {'kind': 'message_someone'},
          ),
          ...base
        ];
      case NeuraMood.tired:
        return [
          const JoyMoment(
            id: 'micro_nap_plan',
            title: 'Rest Plan',
            description: 'Two options: 10-min eyes closed, or a slow walk.',
            type: JoyMomentType.tinyQuest,
            minutes: 2,
            payload: {
              'options': ['eyes_closed_10', 'slow_walk_5']
            },
          ),
          ...base.where((m) => m.minutes <= 3),
        ];
      case NeuraMood.energized:
        return [
          const JoyMoment(
            id: 'creative_sprint',
            title: 'Creative Sprint',
            description: 'Set a 5-min timer and make something tiny.',
            type: JoyMomentType.creativePrompt,
            minutes: 5,
            payload: {'timer': 300},
          ),
          ...base
        ];
      case NeuraMood.calm:
      case NeuraMood.neutral:
        return base;
    }
  }
}
