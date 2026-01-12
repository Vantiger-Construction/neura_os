import 'dream_journal_entry.dart';


class NeuraDreamReplayBuilder {
  String buildMonthlyNarrative(List<DreamJournalEntry> entries) {
    if (entries.isEmpty) {
      return "No dreams to replay this month. Sweet dreams next time!";
    }

    final moodCount = <String, int>{};
    final themes = <String>[];

    for (var entry in entries) {
      moodCount[entry.emotion] = (moodCount[entry.emotion] ?? 0) + 1;
      themes.add(entry.dreamscapeTheme);
    }

    final mostCommonMood = moodCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    final uniqueThemes = themes.toSet().join(", ");

    return "This month, your dreams were mostly filled with a $mostCommonMood feeling.\n"
           "Themes like $uniqueThemes reappeared in your sleep.\n"
           "Here's a dreamy summary of your subconscious journey.";
  }

  String pickMoodBasedVisualCue(String mood) {
    final visuals = {
      "happy": "rising sun and sparkling skies",
      "anxious": "soft mist and shifting clouds",
      "sad": "gentle rain and reflective lakes",
      "focused": "crystal patterns and starlit paths",
      "calm": "floating waves and glowing trees"
    };
    return visuals[mood] ?? "shifting dreamlights";
  }
}