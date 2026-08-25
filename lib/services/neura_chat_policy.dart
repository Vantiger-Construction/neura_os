/// Room-scoped privacy and tool policy for Neura chat.
///
/// The policy is intentionally independent of Flutter widgets so the same
/// checks can be used when tools are advertised to the model and again at
/// execution time. That second check is the security boundary: model output
/// is never trusted just because a tool was advertised earlier in the turn.
class NeuraChatRoomPolicy {
  final String roomId;
  final bool persistMemory;
  final Set<String> allowedTools;

  const NeuraChatRoomPolicy({
    required this.roomId,
    required this.persistMemory,
    required this.allowedTools,
  });

  bool allowsTool(String name) => allowedTools.contains(name);
}

/// A model-requested command that must be applied by the UI/runtime layer.
/// The AI service validates the command against [NeuraChatRoomPolicy] before
/// creating one of these.
class NeuraToolCommand {
  final String name;
  final Map<String, dynamic> arguments;

  const NeuraToolCommand(this.name, this.arguments);
}

class NeuraChatPolicy {
  NeuraChatPolicy._();

  static const String getMoodHistory = 'get_mood_history';
  static const String logMoodEntry = 'log_mood_entry';
  static const String dispatchIntent = 'dispatch_intent';
  static const String setTone = 'set_tone';

  static const Set<String> knownRoomIds = {
    'penthouse',
    'reflection_bay',
    'joy_lounge',
    'mood_den',
    'dream_atrium',
    'legacy_vault',
  };

  static const Set<String> knownTones = {
    'strategist',
    'calm_wellness',
    'warm_companion',
    'cinematic_guide',
    'quiet_private',
  };

  /// Privacy/tool defaults for the rooms that exist in the current app.
  ///
  /// Reflection Bay, Mood Den and Dream Atrium are intentionally ephemeral:
  /// their chat turns remain in the in-memory conversation but are not
  /// written to the encrypted long-term memory graph. Legacy Vault remains
  /// persistent because durable storage is the purpose of that room.
  static NeuraChatRoomPolicy forRoom(String roomId) {
    switch (roomId) {
      case 'reflection_bay':
        return const NeuraChatRoomPolicy(
          roomId: 'reflection_bay',
          persistMemory: false,
          allowedTools: {getMoodHistory, logMoodEntry, setTone},
        );
      case 'mood_den':
        return const NeuraChatRoomPolicy(
          roomId: 'mood_den',
          persistMemory: false,
          allowedTools: {getMoodHistory, logMoodEntry, setTone},
        );
      case 'dream_atrium':
        return const NeuraChatRoomPolicy(
          roomId: 'dream_atrium',
          persistMemory: false,
          allowedTools: {dispatchIntent, setTone},
        );
      case 'joy_lounge':
        return const NeuraChatRoomPolicy(
          roomId: 'joy_lounge',
          persistMemory: true,
          allowedTools: {
            getMoodHistory,
            logMoodEntry,
            dispatchIntent,
            setTone,
          },
        );
      case 'legacy_vault':
        return const NeuraChatRoomPolicy(
          roomId: 'legacy_vault',
          persistMemory: true,
          allowedTools: {dispatchIntent, setTone},
        );
      case 'penthouse':
      default:
        return const NeuraChatRoomPolicy(
          roomId: 'penthouse',
          persistMemory: true,
          allowedTools: {
            getMoodHistory,
            logMoodEntry,
            dispatchIntent,
            setTone,
          },
        );
    }
  }

  /// Tool definitions sent to the model for this room. Execution still calls
  /// [NeuraChatRoomPolicy.allowsTool] again before any side effect occurs.
  static List<Map<String, dynamic>> advertisedTools(
    NeuraChatRoomPolicy policy,
  ) {
    final tools = <Map<String, dynamic>>[];
    for (final name in policy.allowedTools) {
      final definition = _definitionFor(name);
      if (definition != null) tools.add(definition);
    }
    return tools;
  }

  static Map<String, dynamic>? _definitionFor(String name) {
    switch (name) {
      case getMoodHistory:
        return {
          'name': getMoodHistory,
          'description':
              "Request the user's recent mood dates and 0-10 scores for this "
                  'reply. A user confirmation is required and notes are never '
                  'shared.',
          'input_schema': {
            'type': 'object',
            'properties': {
              'limit': {
                'type': 'integer',
                'description':
                    'Maximum recent entries to return. Defaults to 10.',
              },
            },
            'required': <String>[],
          },
        };
      case logMoodEntry:
        return {
          'name': logMoodEntry,
          'description':
              'Record a mood check-in only when the user clearly asks to save '
                  'or log it. Do not log every emotional statement.',
          'input_schema': {
            'type': 'object',
            'properties': {
              'mood0to10': {
                'type': 'integer',
                'description': 'Mood rating from 0 (worst) to 10 (best).',
              },
              'note': {
                'type': 'string',
                'description': 'Short note describing the mood or context.',
              },
            },
            'required': ['mood0to10'],
          },
        };
      case dispatchIntent:
        return {
          'name': dispatchIntent,
          'description':
              'Request navigation to another Neura room when the user clearly '
                  'asks to go there. The UI remains authoritative for room state.',
          'input_schema': {
            'type': 'object',
            'properties': {
              'room': {
                'type': 'string',
                'enum': knownRoomIds.toList(),
                'description': 'Destination Neura room id.',
              },
            },
            'required': ['room'],
          },
        };
      case setTone:
        return {
          'name': setTone,
          'description':
              'Set Neura\'s presentation tone for the current interaction.',
          'input_schema': {
            'type': 'object',
            'properties': {
              'tone': {
                'type': 'string',
                'enum': knownTones.toList(),
              },
            },
            'required': ['tone'],
          },
        };
      default:
        return null;
    }
  }
}
