import 'package:flutter/material.dart';

import '../reliability/safe_boot.dart';
import 'neura_daily_plan.dart';
import 'neura_task_transfer.dart';
import 'neura_task_transfer_screen.dart';

class NeuraDailyPlanScreen extends StatefulWidget {
  const NeuraDailyPlanScreen({super.key});

  @override
  State<NeuraDailyPlanScreen> createState() => _NeuraDailyPlanScreenState();
}

class _NeuraDailyPlanScreenState extends State<NeuraDailyPlanScreen>
    with WidgetsBindingObserver {
  final _plan = NeuraDailyPlan();
  final _goal = TextEditingController();
  final _steps = TextEditingController();
  String? _error;
  int _epoch = 0;
  TextEditingController? _adjustment;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafety);
    SafeBoot.instance.restartRequired.addListener(_onSafety);
  }

  void _clear() {
    _epoch++;
    _adjustment?.clear();
    _goal.clear();
    _steps.clear();
    _plan.clear();
    if (mounted) setState(() => _error = null);
  }

  void _onSafety() {
    if (SafeBoot.instance.safeMode.value ||
        SafeBoot.instance.restartRequired.value) {
      _clear();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafety);
    SafeBoot.instance.restartRequired.removeListener(_onSafety);
    _plan.dispose();
    _goal.dispose();
    _steps.dispose();
    super.dispose();
  }

  void _preview() {
    if (SafeBoot.instance.safeMode.value ||
        SafeBoot.instance.restartRequired.value) {
      return;
    }
    try {
      _plan.preview(_goal.text, _steps.text.split('\n'));
      setState(() => _error = null);
    } on ArgumentError {
      setState(
        () => _error = 'Add a goal and 1–8 steps, up to 160 characters each.',
      );
    }
  }

  Future<void> _smallerStep() async {
    final epoch = _epoch;
    final controller = TextEditingController();
    _adjustment = controller;
    final route = DialogRoute<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Make the next step easier'),
                content: TextField(
                    controller: controller,
                    maxLength: 160,
                    decoration: const InputDecoration(
                        labelText: 'A smaller step',
                        hintText: 'Something you can start in two minutes')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Preview smaller step'))
                ]));
    final accepted = await Navigator.of(context).push(route);
    await route.completed;
    final text = controller.text;
    _adjustment = null;
    controller.dispose();
    if (!mounted || epoch != _epoch || accepted != true) return;
    try {
      _plan.makeCurrentStepSmaller(text);
      _steps.text = _plan.steps.join('\n');
    } on ArgumentError {
      setState(() => _error = 'Enter one smaller step.');
    }
  }

  Future<void> _transfer() async {
    final epoch = _epoch;
    final snapshot = _plan.approved
        ? NeuraTaskSnapshot(goal: _plan.goal, steps: _plan.steps, completed: {
            for (var i = 0; i < _plan.steps.length; i++)
              if (_plan.isComplete(i)) i
          })
        : null;
    final result = await Navigator.push<NeuraTaskSnapshot>(
        context,
        MaterialPageRoute(
            builder: (_) => NeuraTaskTransferScreen(snapshot: snapshot)));
    if (!mounted ||
        epoch != _epoch ||
        result == null ||
        SafeBoot.instance.safeMode.value ||
        SafeBoot.instance.restartRequired.value) {
      return;
    }
    _goal.text = result.goal;
    _steps.text = result.steps.join('\n');
    _plan.previewTransferred(result.goal, result.steps, result.completed);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Plan my day'), actions: [
          IconButton(
              tooltip: 'Continue on another device',
              onPressed: _transfer,
              icon: const Icon(Icons.devices)),
        ]),
        body: AnimatedBuilder(
          animation: _plan,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Choose one goal and a few manageable steps. '
                'This checklist stays in RAM and clears when you leave the app, '
                'close this screen, or enter Safe Mode. Nothing runs automatically.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _goal,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'My goal'),
                onChanged: (_) => _plan.clear(),
              ),
              TextButton.icon(
                onPressed: () {
                  _steps.text =
                      'Choose the smallest part of this goal to start with\n'
                      'Spend five minutes on that first step\n'
                      'Pause and decide whether to continue or adjust';
                  _plan.clear();
                },
                icon: const Icon(Icons.lightbulb_outline),
                label: const Text('Suggest starter steps'),
              ),
              TextField(
                controller: _steps,
                minLines: 3,
                maxLines: 8,
                maxLength: 1287,
                decoration: const InputDecoration(
                  labelText: 'Small steps, one per line',
                  hintText:
                      'Choose a first step that takes five minutes\nTake a short break\nReview what helped',
                ),
                onChanged: (_) => _plan.clear(),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton(
                onPressed: _preview,
                child: const Text('Preview my plan'),
              ),
              if (_plan.steps.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(_plan.goal, style: Theme.of(context).textTheme.titleLarge),
                Text(
                  '${_plan.completedCount} of ${_plan.steps.length} steps complete',
                ),
                if (_plan.approved)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_plan.paused
                                    ? 'Take your time. Your plan is paused.'
                                    : _plan.nextStepIndex == null
                                        ? 'You completed your plan. Notice what helped.'
                                        : 'Next: ${_plan.steps[_plan.nextStepIndex!]}'),
                                if (_plan.nextStepIndex != null) ...[
                                  const Text(
                                      'Try a few minutes, then choose whether to continue. You decide when it is done.'),
                                  Wrap(spacing: 8, children: [
                                    TextButton(
                                        onPressed: () =>
                                            _plan.pause(!_plan.paused),
                                        child: Text(_plan.paused
                                            ? 'Resume plan'
                                            : 'Pause plan')),
                                    TextButton(
                                        onPressed: _smallerStep,
                                        child:
                                            const Text('This feels too big')),
                                  ]),
                                ],
                              ]))),
                for (var index = 0; index < _plan.steps.length; index++)
                  CheckboxListTile(
                    title: Text(_plan.steps[index]),
                    value: _plan.isComplete(index),
                    onChanged: _plan.approved && !_plan.paused
                        ? (value) => _plan.complete(index, value ?? false)
                        : null,
                  ),
                if (!_plan.approved)
                  FilledButton(
                    onPressed: _plan.approve,
                    child: const Text('Use this plan'),
                  ),
              ],
              TextButton(onPressed: _clear, child: const Text('Clear plan')),
            ],
          ),
        ),
      );
}
