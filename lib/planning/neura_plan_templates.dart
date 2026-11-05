/// Optional local starting points. Selecting one creates only an editable draft.
class NeuraPlanTemplate {
  const NeuraPlanTemplate(this.name, this.goal, this.steps);

  final String name;
  final String goal;
  final List<String> steps;

  static const values = [
    NeuraPlanTemplate('Gentle start', 'Make a manageable start', [
      'Choose one thing that matters today',
      'Prepare what I need for the smallest first step',
      'Try that step for five minutes',
      'Pause and decide what feels manageable next',
    ]),
    NeuraPlanTemplate('Focus session', 'Make progress on one task', [
      'Name the result I want from this session',
      'Put aside one distraction',
      'Work on one small part',
      'Write down the next step and take a break',
    ]),
    NeuraPlanTemplate('Evening reset', 'Leave tomorrow a little easier', [
      'Notice one thing I finished or tried today',
      'Tidy one small area',
      'Choose one priority for tomorrow',
      'Put the plan aside for the evening',
    ]),
  ];
}
