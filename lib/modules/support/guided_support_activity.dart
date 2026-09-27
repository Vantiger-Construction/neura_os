/// Fixed, optional wellness activities. No model or emotion inference is used.
enum GuidedSupportActivity {
  quietWriting('Quiet writing', 'Make room for what is on your mind.', [
    GuidedSupportStep(
      'Put it into words',
      'You do not have to explain everything. Write a little, or just pause. '
          'These words stay here temporarily; Neura does not read or save them.',
      prompt: 'What would you like to get off your mind? (optional)',
    ),
    GuidedSupportStep(
      'Leave some room for yourself',
      'You can leave this unfinished. Consider what would make the next few '
          'minutes gentler, or whether you would like to speak with someone.',
    ),
  ]),
  grounding('Grounding pause', 'Notice your surroundings, at your own pace.', [
    GuidedSupportStep(
      'Notice one detail',
      'Choose something nearby that feels comfortable to focus on. '
          'Notice its colour or shape. You can use touch or sound instead, '
          'or skip any step that does not suit you.',
    ),
    GuidedSupportStep(
      'Stay with the present',
      'If comfortable, notice a surface supporting you, or a sound around '
          'you. There is no need to change your breathing or close your eyes.',
    ),
    GuidedSupportStep(
      'Take the next moment gently',
      'Return your attention to the room. You can rest here, change '
          'activities, or choose one small thing to do next.',
    ),
  ]),
  smallPlan('One small plan', 'Choose a manageable next step.', [
    GuidedSupportStep(
      'Choose one thing',
      'What matters in the next few minutes? Choose something you can '
          'influence. It is okay if the bigger problem cannot be solved now.',
      prompt: 'One thing to focus on (optional)',
    ),
    GuidedSupportStep(
      'Make the step smaller',
      'Pick an action that feels manageable: open the document, take a '
          'break, or ask someone for help. You can make it smaller again.',
      prompt: 'My small next step (optional)',
    ),
    GuidedSupportStep(
      'Choose when to try',
      'Decide when you might try that step and whether you need support. '
          'This is a draft for you, with no reminders or tasks created.',
      prompt: 'When, or with whose help? (optional)',
    ),
  ]);

  const GuidedSupportActivity(this.label, this.description, this.steps);

  final String label;
  final String description;
  final List<GuidedSupportStep> steps;
}

class GuidedSupportStep {
  const GuidedSupportStep(this.title, this.body, {this.prompt});

  final String title;
  final String body;
  final String? prompt;
}

enum GuidedSupportFeedback {
  helped('Helped a little'),
  same('About the same'),
  worse('Felt worse'),
  unsure('Not sure');

  const GuidedSupportFeedback(this.label);
  final String label;
}
