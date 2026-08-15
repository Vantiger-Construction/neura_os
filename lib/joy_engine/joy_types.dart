enum NeuraMood { calm, stressed, sad, energized, tired, neutral }

enum NeuraIntent {
  seekingCalm,
  seekingProgress,
  seekingSleep,
  seekingConnection
}

class JoyPreferenceProfile {
  final bool likesHumor;
  final bool likesGames;
  final bool likesReflection;
  final bool likesCreativity;

  const JoyPreferenceProfile({
    this.likesHumor = true,
    this.likesGames = true,
    this.likesReflection = true,
    this.likesCreativity = true,
  });
}

class JoyMoment {
  final String id;
  final String title;
  final String description;
  final JoyMomentType type;
  final int minutes; // target duration
  final Map<String, dynamic> payload;

  const JoyMoment({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.minutes,
    this.payload = const {},
  });
}

enum JoyMomentType {
  breathingGame,
  gratitudeDice,
  tinyQuest,
  gentleJoke,
  creativePrompt,
  musicMood,
}
