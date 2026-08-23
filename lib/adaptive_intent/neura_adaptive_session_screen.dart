import 'dart:async';

import 'package:flutter/material.dart';

import '../cognitive/neura_cognitive_state.dart';
import '../intent_compiler/neura_action_graph.dart';
import 'neura_adaptive_intent_runtime.dart';
import 'neura_adaptive_outcome_loop.dart';
import 'neura_adaptive_plan_session.dart';

class NeuraAdaptiveSessionScreen extends StatefulWidget {
  const NeuraAdaptiveSessionScreen({this.runtime, super.key});

  final NeuraAdaptiveIntentRuntime? runtime;

  @override
  State<NeuraAdaptiveSessionScreen> createState() =>
      _NeuraAdaptiveSessionScreenState();
}

class _NeuraAdaptiveSessionScreenState
    extends State<NeuraAdaptiveSessionScreen> {
  late final NeuraAdaptiveIntentRuntime _runtime;
  late final TextEditingController _outcomeController;
  bool _loading = true;
  Object? _initializationError;
  double _perceivedEffort = 0.50;
  double _satisfaction = 0.70;
  int _interruptions = 0;

  @override
  void initState() {
    super.initState();
    _runtime = widget.runtime ?? NeuraAdaptiveIntentRuntime.instance;
    _outcomeController = TextEditingController(
      text: 'Organize my next three priorities without overwhelming me.',
    );
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _outcomeController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _initializationError = null;
      });
    }
    try {
      await _runtime.controller.initialize();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initializationError = error;
      });
    }
  }

  Future<void> _startSession() async {
    final outcome = _outcomeController.text.trim();
    if (outcome.isEmpty) {
      _showMessage('Describe the outcome you want first.');
      return;
    }
    try {
      await _runtime.startSession(outcome);
    } on FormatException {
      _showMessage('That outcome could not be compiled safely.');
    } on StateError {
      _showMessage(
        _runtime.controller.safeMode
            ? 'Safe Mode blocks active planning sessions.'
            : 'Finish or discard the current session before starting another.',
      );
    }
  }

  Future<void> _completeStep(NeuraPlanStepProgress progress) async {
    var approved = progress.step.requiredApproval == NeuraApprovalTier.none;
    if (!approved) {
      approved = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Confirm local plan change'),
              content: Text(
                '${progress.step.title}\n\n'
                'This records local progress only. It does not perform an '
                'external action.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ) ==
          true;
      if (!approved) return;
    }

    try {
      _runtime.completeStep(
        progress.step.id,
        userGesture: true,
        approvalGranted: approved,
      );
    } on StateError {
      _showMessage('That step cannot be completed in the current state.');
    }
  }

  void _deferStep(NeuraPlanStepProgress progress) {
    try {
      _runtime.deferStep(progress.step.id, userGesture: true);
    } on StateError {
      _showMessage('That step cannot be deferred in the current state.');
    }
  }

  void _resumeStep(NeuraPlanStepProgress progress) {
    try {
      _runtime.resumeStep(progress.step.id, userGesture: true);
    } on StateError {
      _showMessage('That step cannot be resumed in the current state.');
    }
  }

  void _finishSession() {
    try {
      _runtime.finishSession(
        userGesture: true,
        perceivedEffort: _perceivedEffort,
        satisfaction: _satisfaction,
        interruptionCount: _interruptions,
      );
    } on StateError {
      _showMessage(
        'Complete or defer each local step before finishing the session.',
      );
    }
  }

  Future<void> _endSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this session?'),
        content: const Text(
          'Neura will record only derived completion, effort, satisfaction, '
          'and interruption counts. The plan text is not added to the outcome '
          'receipt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep working'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (_runtime.controller.safeMode) {
      _runtime.discardSession(userGesture: true);
      _showMessage('The local session was discarded in Safe Mode.');
      return;
    }

    try {
      _runtime.finishSession(
        userGesture: true,
        abandoned: true,
        perceivedEffort: _perceivedEffort,
        satisfaction: _satisfaction,
        interruptionCount: _interruptions,
      );
    } on StateError {
      _showMessage('The session could not be ended safely.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Adaptive Plan Session')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_initializationError != null && !_runtime.controller.initialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Adaptive Plan Session')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sync_problem_outlined, size: 42),
                const SizedBox(height: 12),
                const Text(
                  'The local Adaptive Intent settings could not be loaded.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => unawaited(_initialize()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _runtime.controller,
      builder: (context, _) => AnimatedBuilder(
        animation: _runtime,
        builder: (context, _) {
          final session = _runtime.session;
          return Scaffold(
            appBar: AppBar(title: const Text('Adaptive Plan Session')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_runtime.controller.safeMode) ...[
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.health_and_safety_outlined),
                      title: Text('Safe Mode is active'),
                      subtitle: Text(
                        'Progress changes and new sessions are blocked. You '
                        'may discard the current in-memory session.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (session == null) ...[
                  if (_runtime.lastOutcome != null) ...[
                    _OutcomeCard(
                      outcome: _runtime.lastOutcome!,
                      adaptation: _runtime.lastAdaptation,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _StartSessionCard(
                    controller: _outcomeController,
                    enabled: !_runtime.controller.safeMode,
                    onStart: () => unawaited(_startSession()),
                  ),
                ] else ...[
                  _SessionHeader(session: session),
                  const SizedBox(height: 12),
                  for (final progress in session.progress) ...[
                    _ProgressCard(
                      progress: progress,
                      safeMode: _runtime.controller.safeMode,
                      onComplete: () => unawaited(_completeStep(progress)),
                      onDefer: () => _deferStep(progress),
                      onResume: () => _resumeStep(progress),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 4),
                  _FeedbackCard(
                    perceivedEffort: _perceivedEffort,
                    satisfaction: _satisfaction,
                    interruptions: _interruptions,
                    enabled: !_runtime.controller.safeMode,
                    onEffortChanged: (value) {
                      setState(() => _perceivedEffort = value);
                    },
                    onSatisfactionChanged: (value) {
                      setState(() => _satisfaction = value);
                    },
                    onInterruptionsChanged: (value) {
                      setState(() => _interruptions = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _SessionActions(
                    session: session,
                    safeMode: _runtime.controller.safeMode,
                    onFinish: _finishSession,
                    onEnd: () => unawaited(_endSession()),
                  ),
                ],
                const SizedBox(height: 28),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StartSessionCard extends StatelessWidget {
  const _StartSessionCard({
    required this.controller,
    required this.enabled,
    required this.onStart,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Start one local plan',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Neura will compile a proposal and track only user-directed '
              'local progress. External steps remain review-only.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 5,
              maxLength: 600,
              enabled: enabled,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Desired outcome',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('adaptive-session-start'),
              onPressed: enabled ? onStart : null,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Start local session'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({required this.session});

  final NeuraAdaptivePlanSession session;

  @override
  Widget build(BuildContext context) {
    final local = session.progress.where(
      (item) => !item.step.blocked && !item.step.effect.isExternal,
    );
    final completed = local.where(
      (item) => item.status == NeuraPlanStepStatus.completed,
    );
    return Card(
      child: ListTile(
        leading: const Icon(Icons.route_outlined),
        title: const Text('Active local plan'),
        subtitle: Text(
          '${completed.length} of ${local.length} local steps completed • '
          '${session.graph.receipt.bandwidthMode.label}',
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.progress,
    required this.safeMode,
    required this.onComplete,
    required this.onDefer,
    required this.onResume,
  });

  final NeuraPlanStepProgress progress;
  final bool safeMode;
  final VoidCallback onComplete;
  final VoidCallback onDefer;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final step = progress.step;
    final external = step.effect.isExternal;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_statusIcon(progress.status)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(step.description),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(label: Text(step.effect.label)),
                Chip(label: Text(_statusLabel(progress.status))),
                if (step.requiredApproval != NeuraApprovalTier.none)
                  const Chip(label: Text('Confirmation required')),
                if (external) const Chip(label: Text('Review-only')),
              ],
            ),
            if (step.blockReason != null) ...[
              const SizedBox(height: 8),
              Text(
                step.blockReason!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (!step.blocked &&
                !external &&
                progress.status != NeuraPlanStepStatus.completed) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (progress.status == NeuraPlanStepStatus.deferred)
                    OutlinedButton.icon(
                      key: ValueKey(
                        'adaptive-session-resume-${progress.step.id}',
                      ),
                      onPressed: safeMode ? null : onResume,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Resume'),
                    )
                  else ...[
                    OutlinedButton.icon(
                      key: ValueKey(
                        'adaptive-session-defer-${progress.step.id}',
                      ),
                      onPressed: safeMode ? null : onDefer,
                      icon: const Icon(Icons.pause_outlined),
                      label: const Text('Defer'),
                    ),
                    FilledButton.icon(
                      key: ValueKey(
                        'adaptive-session-complete-${progress.step.id}',
                      ),
                      onPressed: safeMode ? null : onComplete,
                      icon: const Icon(Icons.check),
                      label: const Text('Complete'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.perceivedEffort,
    required this.satisfaction,
    required this.interruptions,
    required this.enabled,
    required this.onEffortChanged,
    required this.onSatisfactionChanged,
    required this.onInterruptionsChanged,
  });

  final double perceivedEffort;
  final double satisfaction;
  final int interruptions;
  final bool enabled;
  final ValueChanged<double> onEffortChanged;
  final ValueChanged<double> onSatisfactionChanged;
  final ValueChanged<int> onInterruptionsChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.insights_outlined),
        title: const Text('Session feedback'),
        subtitle: const Text('Derived values only; plan text is excluded'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _FeedbackSlider(
            label: 'Perceived effort',
            value: perceivedEffort,
            enabled: enabled,
            onChanged: onEffortChanged,
          ),
          _FeedbackSlider(
            label: 'Satisfaction',
            value: satisfaction,
            enabled: enabled,
            onChanged: onSatisfactionChanged,
          ),
          Row(
            children: [
              const Expanded(child: Text('Interruptions')),
              IconButton(
                tooltip: 'Decrease interruptions',
                onPressed: !enabled || interruptions == 0
                    ? null
                    : () => onInterruptionsChanged(interruptions - 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$interruptions'),
              IconButton(
                tooltip: 'Increase interruptions',
                onPressed: !enabled || interruptions >= 99
                    ? null
                    : () => onInterruptionsChanged(interruptions + 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeedbackSlider extends StatelessWidget {
  const _FeedbackSlider({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 140, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            divisions: 10,
            label: '${(value * 100).round()}%',
            onChanged: enabled ? onChanged : null,
          ),
        ),
        SizedBox(width: 42, child: Text('${(value * 100).round()}%')),
      ],
    );
  }
}

class _SessionActions extends StatelessWidget {
  const _SessionActions({
    required this.session,
    required this.safeMode,
    required this.onFinish,
    required this.onEnd,
  });

  final NeuraAdaptivePlanSession session;
  final bool safeMode;
  final VoidCallback onFinish;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final local = session.progress.where(
      (item) => !item.step.blocked && !item.step.effect.isExternal,
    );
    final hasPending = local.any(
      (item) => item.status == NeuraPlanStepStatus.pending,
    );
    final hasCompleted = local.any(
      (item) => item.status == NeuraPlanStepStatus.completed,
    );
    final canFinish = !safeMode && !hasPending && hasCompleted;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              key: const ValueKey('adaptive-session-finish'),
              onPressed: canFinish ? onFinish : null,
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Finish session'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('adaptive-session-end'),
              onPressed: onEnd,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(safeMode ? 'Discard session' : 'End session'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({required this.outcome, required this.adaptation});

  final NeuraPlanOutcomeReceipt outcome;
  final NeuraOutcomeAdaptation? adaptation;

  @override
  Widget build(BuildContext context) {
    final recommendation = adaptation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Outcome receipt',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${outcome.completedLocalSteps} of ${outcome.totalLocalSteps} '
              'local steps completed • ${outcome.deferredLocalSteps} deferred',
            ),
            const SizedBox(height: 6),
            Text(
              '${(outcome.perceivedEffort * 100).round()}% effort • '
              '${(outcome.satisfaction * 100).round()}% satisfaction • '
              '${outcome.interruptionCount} interruptions',
            ),
            const SizedBox(height: 6),
            Text(
              'Status: ${outcome.status.name} • '
              '${outcome.bandwidthMode.label}',
            ),
            if (recommendation != null) ...[
              const Divider(height: 24),
              Text(
                'Next adaptation: ${recommendation.recommendedMode.label}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '${recommendation.maxPrimaryActions} primary action'
                '${recommendation.maxPrimaryActions == 1 ? '' : 's'} • '
                '${(recommendation.confidence * 100).round()}% confidence',
              ),
              const SizedBox(height: 8),
              for (final reason in recommendation.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $reason'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _statusLabel(NeuraPlanStepStatus status) {
  return switch (status) {
    NeuraPlanStepStatus.pending => 'Pending',
    NeuraPlanStepStatus.completed => 'Completed',
    NeuraPlanStepStatus.deferred => 'Deferred',
    NeuraPlanStepStatus.blocked => 'Blocked',
  };
}

IconData _statusIcon(NeuraPlanStepStatus status) {
  return switch (status) {
    NeuraPlanStepStatus.pending => Icons.radio_button_unchecked,
    NeuraPlanStepStatus.completed => Icons.check_circle_outline,
    NeuraPlanStepStatus.deferred => Icons.pause_circle_outline,
    NeuraPlanStepStatus.blocked => Icons.block_outlined,
  };
}
