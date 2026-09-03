import 'package:flutter/material.dart';

import 'future_paths_simulator.dart';

/// Lets the user list the steps of something they're planning and see how
/// Neura's [NeuraFuturePathsSimulator] would order them under five different
/// priorities. Advice only — nothing here executes on its own.
class DecisionPathScreen extends StatefulWidget {
  const DecisionPathScreen({super.key});

  @override
  State<DecisionPathScreen> createState() => _DecisionPathScreenState();
}

class _DecisionPathScreenState extends State<DecisionPathScreen> {
  static const _simulator = NeuraFuturePathsSimulator();

  final List<NeuraPlanStep> _steps = [];
  List<NeuraFuturePath> _paths = [];
  int _nextId = 0;

  void _addStep(NeuraPlanStep step) {
    setState(() {
      _steps.add(step);
      _paths = const [];
    });
  }

  void _removeStep(String id) {
    setState(() {
      _steps.removeWhere((step) => step.id == id);
      _paths = const [];
    });
  }

  void _simulate() {
    setState(() {
      _paths = _simulator.simulate(_steps);
    });
  }

  Future<void> _openAddStepDialog() async {
    final step = await showDialog<NeuraPlanStep>(
      context: context,
      builder: (context) => _AddStepDialog(id: 'step-${_nextId++}'),
    );
    if (step != null) _addStep(step);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Decision Path Helper')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddStepDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add step'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Text(
            "List the steps of something you're planning, and Neura will "
            'suggest an order for five different priorities: fastest, '
            'safest, cheapest, least effort, and most reversible. This is '
            'advice only — nothing here runs on its own.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_steps.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.list_alt_outlined),
                title: Text('No steps yet'),
                subtitle: Text('Tap "Add step" to start building a plan.'),
              ),
            )
          else
            ..._steps.map(
              (step) => Card(
                child: ListTile(
                  leading: const Icon(Icons.circle_outlined),
                  title: Text(step.title),
                  subtitle: Text(
                    '${step.estimatedDuration.inMinutes}m • '
                    'effort ${step.effort.toStringAsFixed(1)} • '
                    'cost ${step.cost.toStringAsFixed(1)} • '
                    'risk ${step.risk.toStringAsFixed(1)}'
                    '${step.reversible ? '' : ' • not reversible'}'
                    '${step.hasExternalEffect ? ' • external effect' : ''}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove step',
                    onPressed: () => _removeStep(step.id),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (_steps.length >= 2)
            FilledButton.icon(
              onPressed: _simulate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Compare orderings'),
            )
          else if (_steps.length == 1)
            Text(
              'Add at least one more step to compare orderings.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            ),
          const SizedBox(height: 20),
          ..._paths.map((path) => _FuturePathCard(path: path)),
        ],
      ),
    );
  }
}

class _FuturePathCard extends StatelessWidget {
  const _FuturePathCard({required this.path});

  final NeuraFuturePath path;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.route_outlined),
        title: Text(_goalLabel(path.goal)),
        subtitle: Text(
          'Score ${path.score.toStringAsFixed(1)}'
          '${path.requiresApproval ? ' • includes an irreversible or external step' : ''}',
        ),
        children: [
          for (var i = 0; i < path.steps.length; i++)
            ListTile(
              dense: true,
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(path.steps[i].title),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static String _goalLabel(NeuraFuturePathGoal goal) => switch (goal) {
        NeuraFuturePathGoal.fastest => 'Fastest first',
        NeuraFuturePathGoal.safest => 'Safest first',
        NeuraFuturePathGoal.lowestCost => 'Cheapest first',
        NeuraFuturePathGoal.lowestEffort => 'Least effort first',
        NeuraFuturePathGoal.mostReversible => 'Most reversible first',
      };
}

class _AddStepDialog extends StatefulWidget {
  const _AddStepDialog({required this.id});

  final String id;

  @override
  State<_AddStepDialog> createState() => _AddStepDialogState();
}

class _AddStepDialogState extends State<_AddStepDialog> {
  final _titleController = TextEditingController();
  final _minutesController = TextEditingController(text: '30');
  double _effort = 0.5;
  double _cost = 0.5;
  double _risk = 0.2;
  bool _reversible = true;
  bool _hasExternalEffect = false;

  @override
  void dispose() {
    _titleController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final minutes = int.tryParse(_minutesController.text) ?? 30;
    Navigator.of(context).pop(
      NeuraPlanStep(
        id: widget.id,
        title: title,
        estimatedDuration: Duration(minutes: minutes),
        effort: _effort,
        cost: _cost,
        risk: _risk,
        reversible: _reversible,
        hasExternalEffect: _hasExternalEffect,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a step'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Step title'),
            ),
            TextField(
              controller: _minutesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Estimated minutes'),
            ),
            const SizedBox(height: 12),
            _LabeledSlider(
              label: 'Effort',
              value: _effort,
              onChanged: (value) => setState(() => _effort = value),
            ),
            _LabeledSlider(
              label: 'Cost',
              value: _cost,
              onChanged: (value) => setState(() => _cost = value),
            ),
            _LabeledSlider(
              label: 'Risk',
              value: _risk,
              onChanged: (value) => setState(() => _risk = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _reversible,
              onChanged: (value) => setState(() => _reversible = value),
              title: const Text('Reversible'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _hasExternalEffect,
              onChanged: (value) => setState(() => _hasExternalEffect = value),
              title: const Text('Affects something outside the app'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(1)}'),
        Slider(
          value: value,
          min: 0,
          max: 1,
          divisions: 10,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
