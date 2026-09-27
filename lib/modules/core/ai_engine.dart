/// Structured output from Neura's deterministic, on-device fallback.
class NeuraOfflineReply {
  const NeuraOfflineReply({
    required this.text,
    required this.intent,
    this.suggestedSteps = const <String>[],
  });

  final String text;
  final String intent;
  final List<String> suggestedSteps;
}

/// A deterministic local brain for useful replies without a model provider.
///
/// It performs no network access, reads no saved memory, and executes no
/// actions. Suggested steps are plain guidance; side effects still belong to
/// Action Loom and require their own visible approval.
class NeuraAICore {
  NeuraAICore._();
  static final NeuraAICore instance = NeuraAICore._();

  String respond(String message, {String roomId = 'penthouse'}) =>
      respondDetailed(message, roomId: roomId).text;

  NeuraOfflineReply respondDetailed(
    String message, {
    String roomId = 'penthouse',
    bool imageAttached = false,
  }) {
    final m = message.trim().toLowerCase();
    // An unsupported attachment must not mask urgent text in the message.
    if (_containsAny(m, const <String>[
      'suicide',
      'kill myself',
      'hurt myself',
      'immediate danger',
    ])) {
      return const NeuraOfflineReply(
        text: 'Your immediate safety matters more than this chat. '
            'Contact local emergency services now, or move near a trusted '
            'person and open Neura\'s Support Center. I will stay with you '
            'while you take that step.',
        intent: 'urgent_safety',
        suggestedSteps: <String>[
          'Contact local emergency services',
          'Move near a trusted person',
          'Open Support Center',
        ],
      );
    }

    if (imageAttached) {
      return const NeuraOfflineReply(
        text: 'I am staying on-device, so I cannot inspect that image. '
            'Describe what you want me to notice and I can still help.',
        intent: 'image_unavailable_offline',
      );
    }
    if (m.isEmpty) {
      return NeuraOfflineReply(
        text: '${_roomOpening(roomId)} Say the word. I am listening.',
        intent: 'listen',
      );
    }

    if (_containsAny(m, const <String>[
      'anx',
      'panic',
      'stress',
      'overwhelm',
    ])) {
      return const NeuraOfflineReply(
        text: 'Okay. Tiny mission: inhale for 4, hold for 4, and exhale '
            'for 6. Then name the one thing that needs attention first. '
            'You are not broken; you are overloaded.',
        intent: 'grounding',
        suggestedSteps: <String>[
          'Take one 4-4-6 breath',
          'Name the first priority',
          'Choose a ten-minute step',
        ],
      );
    }

    if (_containsAny(m, const <String>['sad', 'down', 'depress', 'lonely'])) {
      return const NeuraOfflineReply(
        text: 'I am here. Let us keep the plan gentle: water, a little '
            'light or fresh air, and one message to a safe person. Small '
            'wins still count.',
        intent: 'gentle_support',
        suggestedSteps: <String>[
          'Drink some water',
          'Find light or fresh air',
          'Message one safe person',
        ],
      );
    }

    if (_containsAny(m, const <String>['angry', 'mad', 'furious'])) {
      return const NeuraOfflineReply(
        text: 'Anger is energy with a story attached. Before acting, name '
            'what was violated: time, respect, trust, or a boundary. Then '
            'choose the smallest response you will still respect tomorrow.',
        intent: 'deescalate',
      );
    }

    if (_containsAny(m, const <String>[
      'help',
      'what should i do',
      'make a plan',
      'where do i start',
    ])) {
      return NeuraOfflineReply(
        text: '${_roomOpening(roomId)} Pick one outcome, shrink it to a '
            'ten-minute task, and decide what “done for now” looks like. '
            'I will not run anything without a separate review and approval.',
        intent: 'small_plan',
        suggestedSteps: const <String>[
          'Choose one outcome',
          'Define a ten-minute task',
          'Set a stop point',
        ],
      );
    }

    if (m.contains('legacy')) {
      return const NeuraOfflineReply(
        text: 'Legacy Vault is the right room for that. Write the meaning '
            'first, keep private records local, and decide explicitly what '
            'future-you should be able to see.',
        intent: 'legacy',
      );
    }

    if (_containsAny(m, const <String>['dream', 'nightmare', 'sleep'])) {
      return const NeuraOfflineReply(
        text: 'We can capture the dream without forcing an interpretation. '
            'Start with the strongest image, the feeling it left, and one '
            'detail you do not want to lose.',
        intent: 'dream_reflection',
        suggestedSteps: <String>[
          'Name the strongest image',
          'Name the feeling',
          'Save one vivid detail',
        ],
      );
    }

    // Default: reflect + nudge.
    return NeuraOfflineReply(
      text: '${_roomOpening(roomId)} What is the one outcome you want from '
          'this: clarity, relief, or a plan?',
      intent: 'clarify',
    );
  }

  static bool _containsAny(String value, List<String> patterns) =>
      patterns.any(value.contains);

  static String _roomOpening(String roomId) => switch (roomId) {
        'reflection_bay' => 'We can take this slowly in Reflection Bay.',
        'joy_lounge' => 'We can keep this light without making it shallow.',
        'mood_den' => 'We can steady things here in the Mood Den.',
        'dream_atrium' => 'There is room to imagine in the Dream Atrium.',
        'legacy_vault' => 'We can handle this carefully in the Legacy Vault.',
        _ => 'I am here with you in the Penthouse.',
      };
}
