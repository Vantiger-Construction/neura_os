class JournalPromptService {
  static const _morning = [
    'What intention do you want to carry into today?',
    'Name three things you are grateful for this morning.',
    'What does a successful day look like for you today?',
    'How are you feeling as you start this new day?',
    'What is one small act of kindness you can offer yourself today?',
  ];
  static const _evening = [
    'What was the highlight of your day, no matter how small?',
    'What challenged you today, and how did you respond?',
    'What did you learn about yourself today?',
    'How did your emotions shift throughout the day?',
    'What are you releasing before you sleep tonight?',
  ];
  static const _byMood = <String, List<String>>{
    'joy': [
      'What sparked this joy? How can you invite more of it?',
      'Who would you like to share this feeling with?',
    ],
    'sadness': [
      'What do you need most right now — rest, connection, or expression?',
      'What would you say to a friend feeling this way?',
    ],
    'anger': [
      'What boundary was crossed? What would honouring it look like?',
      'Beneath the anger, what softer feeling is present?',
    ],
    'fear': [
      'What is the worst realistic outcome, and can you survive it?',
      'What small action would make you feel 1% safer right now?',
    ],
    'calm': [
      'What helped you arrive at this stillness?',
      'What would you like to create from this space of calm?',
    ],
  };

  /// Fetches a prompt based on [mood] and time of day.
  Future<String> fetchPrompt({String mood = '', DateTime? time}) async {
    final selectedTime = time ?? DateTime.now();
    final hour = selectedTime.hour;
    if (mood.isNotEmpty) {
      final moodPrompts = _byMood[mood.toLowerCase()];
      if (moodPrompts != null && moodPrompts.isNotEmpty) {
        final idx = _stableIndex(selectedTime, moodPrompts.length);
        return moodPrompts[idx];
      }
    }
    final pool = hour < 12 ? _morning : _evening;
    final idx = _stableIndex(selectedTime, pool.length);
    return pool[idx];
  }

  int _stableIndex(DateTime time, int length) {
    final daySeed = DateTime(
      time.year,
      time.month,
      time.day,
    ).millisecondsSinceEpoch;
    return (daySeed ~/ Duration.millisecondsPerDay + time.hour) % length;
  }
}
