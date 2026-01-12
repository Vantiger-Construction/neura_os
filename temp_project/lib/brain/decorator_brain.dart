class DecoratorBrainDecision {
  final String mood;
  final String intent;
  final String timeOfDay;

  DecoratorBrainDecision(this.mood, this.intent, this.timeOfDay);
}

class DecoratorBrain {
  DecoratorBrain._();
  static final DecoratorBrain instance = DecoratorBrain._();

  DecoratorBrainDecision decide({
    required String roomId,
    required String mood,
    required String intent,
    required String timeOfDay,
  }) {
    // Calm-first safety bias
    if (mood == "overwhelmed") {
      return DecoratorBrainDecision("calm", "reflection", timeOfDay);
    }

    // Room-specific overrides
    if (roomId == "focus_lab" && mood == "tired") {
      return DecoratorBrainDecision("focus", "mentor", timeOfDay);
    }

    return DecoratorBrainDecision(mood, intent, timeOfDay);
  }
}
