import 'dart:async';

import 'package:flutter/material.dart';

import '../reliability/safe_boot.dart';
import '../teaching/neura_teaching_preferences.dart';
import '../teaching/neura_teaching_service.dart';
import '../teaching/teach_neura_screen.dart';
import 'neura_daily_plan.dart';
import 'neura_plan_templates.dart';
import 'neura_starter_steps.dart';
import 'neura_task_transfer.dart';
import 'neura_task_transfer_screen.dart';

class NeuraDailyPlanScreen extends StatefulWidget {
  const NeuraDailyPlanScreen({super.key, this.teachingService});

  final NeuraTeachingService? teachingService;

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
  Object? _transferRequest;
  TextEditingController? _adjustment;
  bool _focusNext = false;
  late final NeuraTeachingService _teaching;

  bool get _allowed =>
      mounted &&
      ModalRoute.of(context)?.isCurrent != false &&
      !SafeBoot.instance.safeMode.value &&
      !SafeBoot.instance.restartRequired.value &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  @override
  void initState() {
    super.initState();
    _teaching = widget.teachingService ?? NeuraTeachingService.instance;
    _teaching.addListener(_onTeaching);
    unawaited(_loadTeaching());
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafety);
    SafeBoot.instance.restartRequired.addListener(_onSafety);
  }

  Future<void> _loadTeaching() async {
    if (!_teaching.available) return;
    try {
      await _teaching.load();
    } catch (_) {
      // Use the original three-step starter; show unconfirmed settings below.
      // Never overwrite unreadable settings or an existing plan.
    }
  }

  void _onTeaching() {
    if (mounted) setState(() {});
  }

  Future<void> _suggestStarterSteps() async {
    if (!_allowed) return;
    final epoch = _epoch;
    final goal = _goal.text;
    final steps = _steps.text;
    await _loadTeaching();
    if (!_allowed ||
        epoch != _epoch ||
        goal != _goal.text ||
        steps != _steps.text) {
      return;
    }
    _steps.text = neuraStarterSteps(_teaching.current.planSize).join('\n');
    _plan.clear();
  }

  void _clear({bool preserveTransfer = false}) {
    _epoch++;
    if (!preserveTransfer) _transferRequest = null;
    _adjustment?.clear();
    _goal.clear();
    _steps.clear();
    _plan.clear();
    if (mounted) {
      setState(() {
        _error = null;
        _focusNext = false;
      });
    }
  }

  void _onSafety() {
    if (SafeBoot.instance.safeMode.value ||
        SafeBoot.instance.restartRequired.value) {
      _clear();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // The child owns picker/read/decryption revocation. Clear the old plan,
      // but allow its newly reviewed import to return after the picker resumes.
      _clear(preserveTransfer: state != AppLifecycleState.detached);
    }
  }

  @override
  void dispose() {
    _teaching.removeListener(_onTeaching);
    _transferRequest = null;
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafety);
    SafeBoot.instance.restartRequired.removeListener(_onSafety);
    _plan.dispose();
    _goal.dispose();
    _steps.dispose();
    super.dispose();
  }

  void _preview() {
    if (!_allowed) return;
    try {
      _plan.preview(_goal.text, _steps.text.split('\n'));
      setState(() => _error = null);
    } on ArgumentError {
      setState(
        () => _error = 'Add a goal and 1–8 steps, up to 160 characters each.',
      );
    }
  }

  void _editPlan(VoidCallback edit) {
    if (!_allowed) return;
    try {
      edit();
      _steps.text = _plan.steps.join('\n');
      setState(() {
        _error = null;
        _focusNext = false;
      });
    } on ArgumentError {
      setState(() => _error = 'Keep 1–8 steps, up to 160 characters each.');
    }
  }

  Future<void> _chooseTemplate(NeuraPlanTemplate template) async {
    if (!_allowed) return;
    final epoch = _epoch;
    if (_goal.text.isNotEmpty || _steps.text.isNotEmpty) {
      final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Replace this plan?'),
                  content: const Text(
                      'The template replaces this draft and its progress.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Keep my plan')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Use template')),
                  ]));
      if (replace != true || !_allowed || epoch != _epoch) return;
    }
    _clear();
    _goal.text = template.goal;
    _steps.text = template.steps.join('\n');
  }

  Future<void> _editStep(int? index) async {
    if (!_allowed || _adjustment != null) return;
    if (index != null && (index < 0 || index >= _plan.steps.length)) return;
    final epoch = _epoch;
    final controller =
        TextEditingController(text: index == null ? '' : _plan.steps[index]);
    _adjustment = controller;
    final route = DialogRoute<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(index == null ? 'Add a step' : 'Edit step'),
              content: TextField(
                  controller: controller,
                  maxLength: 160,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Step')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Preview change')),
              ],
            ));
    final accepted = await Navigator.of(context).push(route);
    await route.completed;
    final text = controller.text;
    _adjustment = null;
    controller.dispose();
    if (!_allowed || epoch != _epoch || accepted != true) return;
    _editPlan(() =>
        index == null ? _plan.addStep(text) : _plan.editStep(index, text));
  }

  Future<void> _smallerStep() async {
    if (!_allowed || _adjustment != null) return;
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
    if (!_allowed || epoch != _epoch || accepted != true) return;
    try {
      _plan.makeCurrentStepSmaller(text);
      _steps.text = _plan.steps.join('\n');
    } on ArgumentError {
      setState(() => _error = 'Enter one smaller step.');
    }
  }

  Future<void> _transfer() async {
    if (_transferRequest != null ||
        SafeBoot.instance.safeMode.value ||
        SafeBoot.instance.restartRequired.value) {
      return;
    }
    final request = Object();
    _transferRequest = request;
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
    final current = identical(request, _transferRequest);
    if (current) _transferRequest = null;
    if (!mounted ||
        !current ||
        result == null ||
        SafeBoot.instance.safeMode.value ||
        SafeBoot.instance.restartRequired.value ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return;
    }
    _goal.text = result.goal;
    _steps.text = result.steps.join('\n');
    _plan.previewTransferred(result.goal, result.steps, result.completed);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Plan my day'), actions: [
          if (_teaching.available)
            IconButton(
                tooltip: 'Teach Neura',
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => NeuraTeachScreen(service: _teaching)));
                },
                icon: const Icon(Icons.school_outlined)),
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
              PopupMenuButton<NeuraPlanTemplate>(
                tooltip: 'Choose a plan template',
                onSelected: _chooseTemplate,
                itemBuilder: (_) => [
                  for (final template in NeuraPlanTemplate.values)
                    PopupMenuItem(value: template, child: Text(template.name))
                ],
                child: const ListTile(
                    leading: Icon(Icons.list_alt),
                    title: Text('Choose a plan template'),
                    trailing: Icon(Icons.arrow_drop_down)),
              ),
              TextField(
                controller: _goal,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'My goal'),
                onChanged: (_) {
                  _plan.clear();
                  setState(() => _focusNext = false);
                },
              ),
              TextButton.icon(
                onPressed: () => unawaited(_suggestStarterSteps()),
                icon: const Icon(Icons.lightbulb_outline),
                label: const Text('Suggest starter steps'),
              ),
              if (_teaching.current.planSize != null)
                Text('Starter preference: ${_teaching.current.planSize!.label} '
                    '(${_teaching.planIsTemporary ? 'just today' : 'saved'}). '
                    'Your existing plan is unchanged.'),
              if (_teaching.error != null)
                const Text('Saved preferences are not confirmed. '
                    'Starter suggestions use the three-step default.'),
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
                onChanged: (_) {
                  _plan.clear();
                  setState(() => _focusNext = false);
                },
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
                LinearProgressIndicator(
                  value: _plan.completedCount / _plan.steps.length,
                  semanticsLabel: 'Plan progress',
                ),
                Wrap(spacing: 8, children: [
                  TextButton.icon(
                      onPressed:
                          _plan.steps.length < 8 ? () => _editStep(null) : null,
                      icon: const Icon(Icons.add),
                      label: const Text('Add a step')),
                  TextButton.icon(
                      onPressed: _plan.canUndo
                          ? () => _editPlan(_plan.undoEdit)
                          : null,
                      icon: const Icon(Icons.undo),
                      label: const Text('Undo last edit')),
                ]),
                if (_plan.approved)
                  SwitchListTile(
                      title: const Text('Focus on next step'),
                      subtitle:
                          const Text('Show one unfinished step at a time.'),
                      value: _focusNext,
                      onChanged: (value) => setState(() => _focusNext = value)),
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
                  if (!_focusNext ||
                      !_plan.approved ||
                      index == _plan.nextStepIndex)
                    CheckboxListTile(
                      title: Text(_plan.steps[index]),
                      secondary: PopupMenuButton<String>(
                        tooltip: 'Options for step ${index + 1}',
                        onSelected: (action) {
                          switch (action) {
                            case 'edit':
                              unawaited(_editStep(index));
                            case 'up':
                              _editPlan(() => _plan.moveStep(index, index - 1));
                            case 'down':
                              _editPlan(() => _plan.moveStep(index, index + 1));
                            case 'remove':
                              _editPlan(() => _plan.removeStep(index));
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit', child: Text('Edit step')),
                          if (index > 0)
                            const PopupMenuItem(
                                value: 'up', child: Text('Move up')),
                          if (index + 1 < _plan.steps.length)
                            const PopupMenuItem(
                                value: 'down', child: Text('Move down')),
                          if (_plan.steps.length > 1)
                            const PopupMenuItem(
                                value: 'remove', child: Text('Remove step')),
                        ],
                      ),
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
