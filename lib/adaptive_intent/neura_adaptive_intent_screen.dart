import 'dart:async';

import 'package:flutter/material.dart';

import '../cognitive/neura_cognitive_state.dart';
import '../intent_compiler/neura_action_graph.dart';
import 'neura_adaptive_intent_controller.dart';

class NeuraAdaptiveIntentScreen extends StatefulWidget {
  const NeuraAdaptiveIntentScreen({super.key});

  @override
  State<NeuraAdaptiveIntentScreen> createState() =>
      _NeuraAdaptiveIntentScreenState();
}

class _NeuraAdaptiveIntentScreenState extends State<NeuraAdaptiveIntentScreen> {
  final _controller = NeuraAdaptiveIntentController.instance;
  late final TextEditingController _outcomeController;
  bool _loading = true;
  Object? _initializationError;

  @override
  void initState() {
    super.initState();
    _outcomeController = TextEditingController(
      text: 'Help me organize this week without overwhelming me.',
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
      await _controller.initialize();
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

  void _compile() {
    final outcome = _outcomeController.text.trim();
    if (outcome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Describe the outcome you want first.')),
      );
      return;
    }
    try {
      _controller.compileOutcome(outcome);
    } on StateError {
      unawaited(_initialize());
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That outcome could not be compiled safely.'),
        ),
      );
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Adaptive Intent?'),
        content: const Text(
          'This restores the local capacity signals and personal constitution '
          'to their defaults. Compiled goal text is never saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _controller.resetPersistedState();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adaptive Intent settings could not be reset.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Adaptive Intent OS')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final initializationError = _initializationError;
    if (initializationError != null && !_controller.initialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Adaptive Intent OS')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sync_problem_outlined, size: 42),
                const SizedBox(height: 12),
                const Text(
                  'Adaptive Intent could not load its local settings.',
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
      animation: _controller,
      builder: (context, _) {
        final state = _controller.state;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Adaptive Intent OS'),
            actions: [
              IconButton(
                tooltip: 'Clear compiled plan',
                onPressed: _controller.plan == null
                    ? null
                    : _controller.clearPlan,
                icon: const Icon(Icons.restart_alt),
              ),
              IconButton(
                tooltip: 'Reset local Adaptive Intent settings',
                onPressed: () => unawaited(_confirmReset()),
                icon: const Icon(Icons.settings_backup_restore),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_controller.lastPersistenceError != null) ...[
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.save_outlined),
                    title: Text('Settings are not saved yet'),
                    subtitle: Text(
                      'The current session still works. Neura will retry after '
                      'the next change.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _StateCard(controller: _controller),
              const SizedBox(height: 12),
              _SignalCard(controller: _controller),
              const SizedBox(height: 12),
              _ConstitutionCard(controller: _controller),
              const SizedBox(height: 12),
              _IntentCard(
                outcomeController: _outcomeController,
                onCompile: _compile,
                mode: state.mode,
              ),
              if (_controller.plan != null) ...[
                const SizedBox(height: 12),
                _PlanCard(graph: _controller.plan!),
              ],
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.controller});

  final NeuraAdaptiveIntentController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final color = _modeColor(context, state.mode);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_modeIcon(state.mode), color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    state.mode.label,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (controller.safeMode)
                  const Chip(
                    avatar: Icon(Icons.health_and_safety, size: 18),
                    label: Text('Safe Mode'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(state.mode.summary),
            const SizedBox(height: 14),
            _MetricBar(
              label: 'Available bandwidth',
              value: state.availableBandwidth,
            ),
            const SizedBox(height: 8),
            _MetricBar(label: 'Cognitive load', value: state.cognitiveLoad),
            const SizedBox(height: 8),
            _MetricBar(label: 'Confidence', value: state.confidence),
            const SizedBox(height: 12),
            for (final reason in state.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 17),
                    const SizedBox(width: 7),
                    Expanded(child: Text(reason)),
                  ],
                ),
              ),
            const Divider(height: 24),
            Text(
              'Interface policy: ${controller.interfacePolicy.maxPrimaryActions} '
              'primary action'
              '${controller.interfacePolicy.maxPrimaryActions == 1 ? '' : 's'}, '
              '${controller.interfacePolicy.externalEffectsAllowed ? 'external effects require approval' : 'external effects blocked'}.',
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.controller});

  final NeuraAdaptiveIntentController controller;

  @override
  Widget build(BuildContext context) {
    final signals = controller.signals;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.monitor_heart_outlined),
        title: const Text('Current capacity signals'),
        subtitle: const Text('Local estimates only — no medical diagnosis'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          _SignalSlider(
            label: 'Energy',
            value: signals.energy,
            onChanged: (value) => controller.updateSignals(energy: value),
          ),
          _SignalSlider(
            label: 'Focus',
            value: signals.focus,
            onChanged: (value) => controller.updateSignals(focus: value),
          ),
          _SignalSlider(
            label: 'Mental load',
            value: signals.cognitiveLoad,
            onChanged: (value) =>
                controller.updateSignals(cognitiveLoad: value),
          ),
          _SignalSlider(
            label: 'Urgency',
            value: signals.urgency,
            onChanged: (value) => controller.updateSignals(urgency: value),
          ),
          _SignalSlider(
            label: 'Task switching',
            value: signals.taskSwitchRate,
            onChanged: (value) =>
                controller.updateSignals(taskSwitchRate: value),
          ),
          _SignalSlider(
            label: 'Completion momentum',
            value: signals.completionRate,
            onChanged: (value) =>
                controller.updateSignals(completionRate: value),
          ),
          _SignalSlider(
            label: 'Notification pressure',
            value: signals.notificationPressure,
            onChanged: (value) =>
                controller.updateSignals(notificationPressure: value),
          ),
        ],
      ),
    );
  }
}

class _ConstitutionCard extends StatelessWidget {
  const _ConstitutionCard({required this.controller});

  final NeuraAdaptiveIntentController controller;

  @override
  Widget build(BuildContext context) {
    final constitution = controller.constitution;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.gavel_outlined),
        title: const Text('Personal constitution'),
        subtitle: const Text('Machine-enforced boundaries for every plan'),
        childrenPadding: const EdgeInsets.only(bottom: 12),
        children: [
          SwitchListTile(
            title: const Text('Allow cloud AI steps'),
            subtitle: const Text('Still requires elevated approval'),
            value: constitution.allowCloudAi,
            onChanged: controller.safeMode
                ? null
                : (value) => controller.updateConstitution(
                    constitution.copyWith(allowCloudAi: value),
                  ),
          ),
          SwitchListTile(
            title: const Text('Allow external messages'),
            subtitle: const Text('A preview remains required by default'),
            value: constitution.allowExternalMessages,
            onChanged: controller.safeMode
                ? null
                : (value) => controller.updateConstitution(
                    constitution.copyWith(allowExternalMessages: value),
                  ),
          ),
          SwitchListTile(
            title: const Text('Require external preview'),
            value: constitution.requireExternalPreview,
            onChanged: (value) => controller.updateConstitution(
              constitution.copyWith(requireExternalPreview: value),
            ),
          ),
          SwitchListTile(
            title: const Text('Allow purchases'),
            subtitle: const Text('Fresh elevated approval remains mandatory'),
            value: constitution.allowPurchases,
            onChanged: controller.safeMode
                ? null
                : (value) => controller.updateConstitution(
                    constitution.copyWith(allowPurchases: value),
                  ),
          ),
          SwitchListTile(
            title: const Text('Keep sensitive content local'),
            value: constitution.keepSensitiveContentLocal,
            onChanged: (value) => controller.updateConstitution(
              constitution.copyWith(keepSensitiveContentLocal: value),
            ),
          ),
          SwitchListTile(
            title: const Text('Allow calendar drafts'),
            value: constitution.allowCalendarWrites,
            onChanged: controller.safeMode
                ? null
                : (value) => controller.updateConstitution(
                    constitution.copyWith(allowCalendarWrites: value),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: _HourPicker(
                    label: 'Work starts',
                    value: constitution.workHoursStart,
                    onChanged: (value) => controller.updateConstitution(
                      constitution.copyWith(workHoursStart: value),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _HourPicker(
                    label: 'Work ends',
                    value: constitution.workHoursEnd,
                    onChanged: (value) => controller.updateConstitution(
                      constitution.copyWith(workHoursEnd: value),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HourPicker extends StatelessWidget {
  const _HourPicker({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: value.clamp(0, 23).toInt(),
          items: [
            for (var hour = 0; hour < 24; hour += 1)
              DropdownMenuItem(
                value: hour,
                child: Text('${hour.toString().padLeft(2, '0')}:00'),
              ),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _IntentCard extends StatelessWidget {
  const _IntentCard({
    required this.outcomeController,
    required this.onCompile,
    required this.mode,
  });

  final TextEditingController outcomeController;
  final VoidCallback onCompile;
  final NeuraBandwidthMode mode;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Desired outcome',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: outcomeController,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Describe what you want Neura to help accomplish.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onCompile,
              icon: const Icon(Icons.account_tree_outlined),
              label: Text('Compile ${mode.label} plan'),
            ),
            const SizedBox(height: 8),
            const Text(
              'The compiler creates a reversible proposal only. It does not '
              'send messages, change calendars, purchase anything, or call '
              'cloud services.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.graph});

  final NeuraActionGraph graph;

  @override
  Widget build(BuildContext context) {
    final active = graph.steps.where((step) => !step.blocked).toList();
    final blocked = graph.blockedSteps;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(graph.outcome, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Intent: ${graph.intent.kind.name} • '
              '${graph.receipt.bandwidthMode.label}',
            ),
            const Divider(height: 24),
            for (final step in active) _StepTile(step: step),
            if (blocked.isNotEmpty) ...[
              const Divider(height: 28),
              Text(
                'Blocked by policy',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final step in blocked) _StepTile(step: step),
            ],
            const Divider(height: 28),
            Text(
              'Decision receipt',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            SelectableText(graph.receipt.id),
            const SizedBox(height: 8),
            Text(
              '${graph.receipt.blockedStepCount} blocked • '
              '${graph.receipt.approvalStepCount} require approval • '
              '${(graph.receipt.confidence * 100).round()}% confidence',
            ),
            const SizedBox(height: 10),
            for (final reason in graph.receipt.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $reason'),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});

  final NeuraActionStep step;

  @override
  Widget build(BuildContext context) {
    final color = step.blocked
        ? Theme.of(context).colorScheme.error
        : step.deferred
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          leading: Icon(_effectIcon(step.effect), color: color),
          title: Text(step.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.description),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Chip(label: Text(step.effect.label)),
                  Chip(
                    label: Text(switch (step.requiredApproval) {
                      NeuraApprovalTier.none => 'No approval',
                      NeuraApprovalTier.confirm => 'Confirm',
                      NeuraApprovalTier.elevated => 'Elevated approval',
                    }),
                  ),
                  if (step.deferred) const Chip(label: Text('Deferred')),
                  if (step.reversible) const Chip(label: Text('Reversible')),
                ],
              ),
              if (step.blockReason != null) ...[
                const SizedBox(height: 6),
                Text(
                  step.blockReason!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalSlider extends StatelessWidget {
  const _SignalSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 150, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 1.0).toDouble(),
            divisions: 20,
            label: '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text('${(value * 100).round()}%', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _MetricBar extends StatelessWidget {
  const _MetricBar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 145, child: Text(label)),
        Expanded(child: LinearProgressIndicator(value: value)),
        const SizedBox(width: 10),
        Text('${(value * 100).round()}%'),
      ],
    );
  }
}

Color _modeColor(BuildContext context, NeuraBandwidthMode mode) {
  return switch (mode) {
    NeuraBandwidthMode.recovery => Theme.of(context).colorScheme.error,
    NeuraBandwidthMode.simplified => Theme.of(context).colorScheme.tertiary,
    NeuraBandwidthMode.balanced => Theme.of(context).colorScheme.primary,
    NeuraBandwidthMode.deepFocus => Theme.of(context).colorScheme.secondary,
  };
}

IconData _modeIcon(NeuraBandwidthMode mode) {
  return switch (mode) {
    NeuraBandwidthMode.recovery => Icons.spa_outlined,
    NeuraBandwidthMode.simplified => Icons.filter_3_outlined,
    NeuraBandwidthMode.balanced => Icons.balance_outlined,
    NeuraBandwidthMode.deepFocus => Icons.center_focus_strong,
  };
}

IconData _effectIcon(NeuraActionEffect effect) {
  return switch (effect) {
    NeuraActionEffect.localRead => Icons.visibility_outlined,
    NeuraActionEffect.localWrite => Icons.edit_note_outlined,
    NeuraActionEffect.notification => Icons.notifications_paused_outlined,
    NeuraActionEffect.calendar => Icons.calendar_month_outlined,
    NeuraActionEffect.externalMessage => Icons.send_outlined,
    NeuraActionEffect.purchase => Icons.shopping_cart_outlined,
    NeuraActionEffect.cloudRequest => Icons.cloud_outlined,
  };
}
