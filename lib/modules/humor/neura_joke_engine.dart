import 'dart:math';

/// Curated joke pool. Rebuilt three times across old, never-shipped repos
/// (neura_ai_joke_engine.dart, neura_humor_engine.dart,
/// neura_joke_engine_upgraded.dart) before finally landing here — the actual
/// joke text is reused from the last of those, the surrounding logic is new.
class NeuraJokeEngine {
  static const List<String> cleanJokes = [
    "Why don't skeletons fight each other? They don't have the guts.",
    'Why did the scarecrow win an award? Because he was outstanding in his field!',
    "Why can't your nose be 12 inches long? Because then it would be a foot!",
    "What did one wall say to the other? I'll meet you at the corner!",
    'Why did the math book look sad? It had too many problems.',
    "I would tell you a chemistry joke, but I know I wouldn't get a reaction.",
    "I'm reading a book about anti-gravity. It's impossible to put down.",
  ];

  static const List<String> spicyJokes = [
    "Why don't oysters donate to charity? Because they're shellfish.",
    'I asked the librarian if they had any books on paranoia… she whispered, "They\'re right behind you."',
    'They say money talks, but mine just waves goodbye.',
    'I told my wife she should embrace her mistakes… she hugged me.',
    "Why do cows wear bells? Because their horns don't work!",
  ];

  /// Picks a random joke, optionally including the spicier pool, and
  /// avoiding [exclude] (disliked jokes, or the just-shown one) where a
  /// clean-enough alternative still exists.
  static String randomJoke({required bool includeSpicy, Set<String> exclude = const {}}) {
    final pool = includeSpicy ? [...cleanJokes, ...spicyJokes] : cleanJokes;
    final available = pool.where((j) => !exclude.contains(j)).toList();
    final choices = available.isEmpty ? pool : available;
    return choices[Random().nextInt(choices.length)];
  }
}
