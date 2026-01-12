import 'dart:math';

class NeuraHumorEngine {
  final Random _random = Random();
  final List<String> _favorites = [];
  
  final List<String> _jokes = [
    "Why don't scientists trust atoms? Because they make up everything!",
    "What do you call a bear with no teeth? A gummy bear!",
    "Why did the scarecrow win an award? He was outstanding in his field!",
    "What do you call a fake noodle? An impasta!",
    "Why don't eggs tell jokes? They'd crack each other up!",
  ];

  void init() {
    // Initialize the humor engine
  }

  String getRandomJoke() {
    return _jokes[_random.nextInt(_jokes.length)];
  }
  
  String getJokeForMood(String mood) {
    // Return mood-appropriate jokes
    return getRandomJoke();
  }

  String getJoke({bool cleanOnly = true}) {
    return getRandomJoke();
  }

  Future<void> rateJoke(String joke, {required bool like}) async {
    if (like && !_favorites.contains(joke)) {
      _favorites.add(joke);
    }
  }

  Future<void> tellFavoriteJoke() async {
    if (_favorites.isNotEmpty) {
      // Play a random favorite joke
      _favorites[_random.nextInt(_favorites.length)];
    }
  }
}
