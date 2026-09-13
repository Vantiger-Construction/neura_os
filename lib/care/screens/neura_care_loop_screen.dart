import 'package:flutter/material.dart';

import '../../modules/mood/mood_models.dart';
import '../../modules/mood/mood_store.dart';
import '../../modules/support/support_center_screen.dart';
import '../../reliability/safe_boot.dart';
import '../models/neura_care_plan.dart';
import '../services/neura_care_loop_service.dart';

class NeuraCareLoopScreen extends StatefulWidget {
  const NeuraCareLoopScreen({super.key});

  @override
  State<NeuraCareLoopScreen> createState() => _NeuraCareLoopScreenState();
}

class _NeuraCareLoopScreenState extends State<NeuraCareLoopScreen> {
  static const _planner = NeuraCareLoopService();

  final _note = TextEditingController();
  int _mood = 5;
  int _energy = 5;
  int _overwhelm = 5;
  NeuraCareNeed _need = NeuraCareNeed.settle;
  bool _feelsUnsafe = false;
  bool _saving = false;
  bool _saved = false;
  NeuraCarePlan? _plan;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  NeuraCareCheckIn get _checkIn => NeuraCareCheckIn(
        mood0to10: _mood,
        energy0to10: _energy,
        overwhelm0to10: _overwhelm,
        need: _need,
        feelsUnsafe: _feelsUnsafe,
      );

  void _buildPlan() {
    setState(() {
      _plan = _planner.buildPlan(_checkIn);
      _saved = false;
    });
  }

  Future<void> _saveLocally() async {
    if (_saving) return;
    setState(() => _saving = true);
    final details = <String>[
      'Care Loop: ${_need.label}',
      'Energy $_energy/10',
      'Overwhelm $_overwhelm/10',
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
    ];
    try {
      await MoodStore.instance.add(
        MoodEntry(
          timestamp: DateTime.now(),
          mood0to10: _mood,
          note: details.join(' · '),
        ),
      );
      if (!mounted) return;
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to encrypted local mood history.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Local save did not complete. Nothing was uploaded.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openSupportCenter() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SupportCenterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Neura Care Loop')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: SafeBoot.instance.safeMode,
            builder: (context, safeMode, _) => _PrivacyCard(
              safeMode: safeMode,
            ),
          ),
          const SizedBox(height: 16),
          Text('1 · Notice', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text(
            'Use your own read of this moment. Neura does not diagnose or '
            'silently analyze your journal.',
          ),
          const SizedBox(height: 12),
          _MetricSlider(
            label: 'Mood',
            lowLabel: 'rough',
            highLabel: 'good',
            value: _mood,
            onChanged: (value) => setState(() => _mood = value),
          ),
          _MetricSlider(
            label: 'Energy',
            lowLabel: 'empty',
            highLabel: 'full',
            value: _energy,
            onChanged: (value) => setState(() => _energy = value),
          ),
          _MetricSlider(
            label: 'Overwhelm',
            lowLabel: 'steady',
            highLabel: 'flooded',
            value: _overwhelm,
            onChanged: (value) => setState(() => _overwhelm = value),
          ),
          const SizedBox(height: 16),
          Text(
            '2 · What would help?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: NeuraCareNeed.values
                .map(
                  (need) => ChoiceChip(
                    label: Text(need.label),
                    selected: _need == need,
                    onSelected: (_) => setState(() => _need = need),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Card(
            color: _feelsUnsafe
                ? Theme.of(context).colorScheme.errorContainer
                : null,
            child: SwitchListTile(
              value: _feelsUnsafe,
              onChanged: (value) {
                setState(() {
                  _feelsUnsafe = value;
                  _plan = value ? _planner.buildPlan(_checkIn) : null;
                });
              },
              title: const Text('I may not be safe right now'),
              subtitle: const Text(
                'Use this when immediate human or emergency support may be '
                'needed. Neura will not try to handle a crisis alone.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _buildPlan,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Choose one care step'),
          ),
          if (plan != null) ...[
            const SizedBox(height: 20),
            _CarePlanCard(plan: plan, onOpenSupport: _openSupportCenter),
            const SizedBox(height: 20),
            Text(
              '3 · Reflect only if you want',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Private note (optional)',
                hintText: 'What helped, or what do you need next?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _saving || _saved ? null : _saveLocally,
              icon: const Icon(Icons.lock_outline),
              label: Text(
                _saved
                    ? 'Saved locally'
                    : _saving
                        ? 'Saving locally…'
                        : 'Save encrypted local check-in',
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Saving is optional. Until you tap the button, this check-in '
              'exists only on this screen. No cloud request is made.',
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Neura supports self-care; it is not a clinician or emergency '
            'service. Persistent or worsening symptoms deserve help from a '
            'qualified health professional.',
            style: TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({required this.safeMode});

  final bool safeMode;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(safeMode ? Icons.shield_outlined : Icons.favorite_outline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    safeMode
                        ? 'Safe Mode · local care only'
                        : 'Private by default',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'No model, microphone, camera, background listener, or '
                    'network request is used by this Care Loop.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricSlider extends StatelessWidget {
  const _MetricSlider({
    required this.label,
    required this.lowLabel,
    required this.highLabel,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String lowLabel;
  final String highLabel;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: '$value out of 10',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text('$value / 10'),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            label: '$value',
            onChanged: (next) => onChanged(next.round()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(lowLabel), Text(highLabel)],
          ),
        ],
      ),
    );
  }
}

class _CarePlanCard extends StatelessWidget {
  const _CarePlanCard({
    required this.plan,
    required this.onOpenSupport,
  });

  final NeuraCarePlan plan;
  final VoidCallback onOpenSupport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: plan.requiresImmediateSupport ? colors.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plan.summary, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            _ActionDetails(label: 'Start here', action: plan.primaryAction),
            const Divider(height: 28),
            _ActionDetails(
              label: 'If that does not fit',
              action: plan.alternativeAction,
            ),
            if (plan.requiresImmediateSupport ||
                plan.primaryAction.kind == NeuraCareActionKind.connection) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onOpenSupport,
                icon: const Icon(Icons.people_outline),
                label: const Text('Open support options'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionDetails extends StatelessWidget {
  const _ActionDetails({required this.label, required this.action});

  final String label;
  final NeuraCareAction action;

  @override
  Widget build(BuildContext context) {
    final duration = action.durationMinutes == 0
        ? 'Now'
        : '${action.durationMinutes} min';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                action.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Chip(label: Text(duration)),
          ],
        ),
        const SizedBox(height: 4),
        Text(action.guidance),
      ],
    );
  }
}
