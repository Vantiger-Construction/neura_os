import 'package:flutter/material.dart';

import '../reliability/safe_boot.dart';
import 'neura_daily_plan.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafety);
  }

  void _clear() {
    _goal.clear();
    _steps.clear();
    _plan.clear();
    if (mounted) setState(() => _error = null);
  }

  void _onSafety() {
    if (SafeBoot.instance.safeMode.value) _clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafety);
    _plan.dispose();
    _goal.dispose();
    _steps.dispose();
    super.dispose();
  }

  void _preview() {
    try {
      _plan.preview(_goal.text, _steps.text.split('\n'));
      setState(() => _error = null);
    } on ArgumentError {
      setState(
        () => _error = 'Add a goal and 1–8 steps, up to 160 characters each.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Plan my day')),
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
                for (var index = 0; index < _plan.steps.length; index++)
                  CheckboxListTile(
                    title: Text(_plan.steps[index]),
                    value: _plan.isComplete(index),
                    onChanged: _plan.approved
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
