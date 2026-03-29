import 'package:flutter/material.dart';

/// Cognitive Behavioral Therapy exercise library.
class CbtExercise {
  final String id;
  final String title;
  final String description;
  final List<String> steps;

  const CbtExercise({
    required this.id,
    required this.title,
    required this.description,
    required this.steps,
  });
}

class CbtExerciseLibrary {
  static const exercises = <CbtExercise>[
    CbtExercise(
      id: 'thought_record',
      title: 'Thought Record',
      description: 'Identify and challenge unhelpful thoughts.',
      steps: [
        'Notice the situation that triggered the feeling.',
        'Write down the automatic thought.',
        'Rate how strongly you believe it (0-100%).',
        'List evidence for and against.',
        'Write a more balanced thought.',
        'Re-rate your belief in the original thought.',
      ],
    ),
    CbtExercise(
      id: 'behavioral_activation',
      title: 'Behavioral Activation',
      description: 'Schedule small, meaningful activities to lift your mood.',
      steps: [
        'Pick one activity you used to enjoy.',
        'Schedule it for a specific time today.',
        'Do it even if motivation is low.',
        'Rate your mood before and after.',
      ],
    ),
    CbtExercise(
      id: 'grounding_5_4_3_2_1',
      title: '5-4-3-2-1 Grounding',
      description: 'Use your senses to anchor yourself in the present.',
      steps: [
        'Name 5 things you can see.',
        'Name 4 things you can touch.',
        'Name 3 things you can hear.',
        'Name 2 things you can smell.',
        'Name 1 thing you can taste.',
      ],
    ),
  ];
}

class CbtExercisesScreen extends StatelessWidget {
  const CbtExercisesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CBT Exercises')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: CbtExerciseLibrary.exercises.length,
        itemBuilder: (context, index) {
          final ex = CbtExerciseLibrary.exercises[index];
          return Card(
            child: ExpansionTile(
              title: Text(ex.title),
              subtitle: Text(ex.description),
              children: [
                for (int i = 0; i < ex.steps.length; i++)
                  ListTile(
                    leading: CircleAvatar(
                      radius: 12,
                      child: Text('${i + 1}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                    title: Text(ex.steps[i]),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
