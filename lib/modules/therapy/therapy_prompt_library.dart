import 'therapy_models.dart';

/// Curated reflection prompts, one list per framework. Sourced from an old,
/// never-shipped "TherapyCBTModule" package that had just 1-2 prompts per
/// method as placeholders - expanded here to a usable starter set.
class TherapyPromptLibrary {
  static const List<TherapyPrompt> cbt = [
    TherapyPrompt(
      id: 'cbt1',
      title: 'Thought Challenge',
      instruction: 'Describe a recent negative thought. What evidence supports it? What evidence goes against it?',
      method: 'CBT',
    ),
    TherapyPrompt(
      id: 'cbt2',
      title: 'Cognitive Distortions',
      instruction: 'What thinking error might have occurred? (e.g. catastrophizing, black-and-white thinking, mind reading)',
      method: 'CBT',
    ),
    TherapyPrompt(
      id: 'cbt3',
      title: 'Reframe',
      instruction: "Write the thought again, but more balanced - what's a fairer way to see the same situation?",
      method: 'CBT',
    ),
  ];

  static const List<TherapyPrompt> dbt = [
    TherapyPrompt(
      id: 'dbt1',
      title: 'Emotion Regulation',
      instruction: 'How did you manage a strong emotion today? What skill did you use, or wish you had?',
      method: 'DBT',
    ),
    TherapyPrompt(
      id: 'dbt2',
      title: 'Opposite Action',
      instruction: "Name an emotion you felt today. What would 'opposite action' look like for it?",
      method: 'DBT',
    ),
  ];

  static const List<TherapyPrompt> act = [
    TherapyPrompt(
      id: 'act1',
      title: 'Values Check',
      instruction: 'What action did you take today that lined up with what actually matters to you?',
      method: 'ACT',
    ),
    TherapyPrompt(
      id: 'act2',
      title: 'Making Room',
      instruction: 'What difficult feeling showed up today? Could you let it be there without fighting it?',
      method: 'ACT',
    ),
  ];

  static List<String> get methods => const ['CBT', 'DBT', 'ACT'];

  static List<TherapyPrompt> forMethod(String method) {
    switch (method) {
      case 'CBT':
        return cbt;
      case 'DBT':
        return dbt;
      case 'ACT':
        return act;
      default:
        return const [];
    }
  }
}
