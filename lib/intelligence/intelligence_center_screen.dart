import 'dart:async';

import 'package:flutter/material.dart';

import '../reliability/safe_boot.dart';
import 'capability_registry.dart';
import 'intelligence_preferences.dart';
import 'models.dart';
import 'neura_intelligence_controller.dart';

class NeuraIntelligenceCenterScreen extends StatefulWidget {
  const NeuraIntelligenceCenterScreen({super.key});

  @override
  State<NeuraIntelligenceCenterScreen> createState() =>
      _NeuraIntelligenceCenterScreenState();
}

class _NeuraIntelligenceCenterScreenState
    extends State<NeuraIntelligenceCenterScreen> {
  final _controller = NeuraIntelligenceController.instance;
  final _registry = NeuraCapabilityRegistry();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.initialize().catchError((_) {}));
  }

  void _save(NeuraIntelligencePreferences preferences) {
    unawaited(
      _controller.updatePreferences(preferences).catchError((Object error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Could not save intelligence settings.')),
          );
        }
      }),
    );
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear decision receipts?'),
        content: const Text(
          'This removes the recent receipt list from Neura Intelligence. '
          'Operational audit metadata in Diagnostics is not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear receipts'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Neura Intelligence')),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final preferences = _controller.preferences;
          final records = _controller.records.reversed.take(20).toList();
          final now = DateTime.now();
          final paused = preferences.pausedUntil != null &&
              now.isBefore(preferences.pausedUntil!);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.hub_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Intelligence Fabric',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: SafeBoot.instance.safeMode,
                            builder: (context, safeMode, _) => Chip(
                              label: Text(
                                safeMode
                                    ? 'Safe Mode'
                                    : paused
                                        ? 'Paused'
                                        : preferences.enabled
                                            ? 'On-device'
                                            : 'Off',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Neura fuses local signals, lets deterministic specialists '
                        'propose opportunities, and explains every decision. It '
                        'cannot silently perform sensitive or external actions.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (paused)
                            FilledButton.tonalIcon(
                              onPressed: () => unawaited(
                                _controller.resume().catchError((_) {}),
                              ),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Resume'),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: () => unawaited(
                                _controller
                                    .pauseFor(const Duration(hours: 24))
                                    .catchError((_) {}),
                              ),
                              icon: const Icon(Icons.pause),
                              label: const Text('Pause 24 hours'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Signal & attention controls',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      value: preferences.enabled,
                      onChanged: (value) =>
                          _save(preferences.copyWith(enabled: value)),
                      secondary: const Icon(Icons.auto_awesome_outlined),
                      title: const Text('Proactive intelligence'),
                      subtitle: const Text(
                        'Allow optional, dismissible suggestions on the dashboard.',
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: preferences.allowSensitiveSignals,
                      onChanged: (value) => _save(
                        preferences.copyWith(allowSensitiveSignals: value),
                      ),
                      secondary: const Icon(Icons.visibility_outlined),
                      title: const Text('Sensitive local signals'),
                      subtitle: const Text(
                        'Off by default. Journal and therapy text remain excluded.',
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: preferences.showDecisionReasons,
                      onChanged: (value) => _save(
                        preferences.copyWith(showDecisionReasons: value),
                      ),
                      secondary: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Show “Why?” on suggestions'),
                      subtitle: const Text(
                          'Expose score, evidence count, and policy reasons.'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.notifications_paused_outlined),
                      title: Text(
                        'Daily suggestion limit: '
                        '${preferences.maxDailySuggestions}',
                      ),
                      subtitle: Slider(
                        value: preferences.maxDailySuggestions.toDouble(),
                        min: 1,
                        max: 6,
                        divisions: 5,
                        label: preferences.maxDailySuggestions.toString(),
                        onChanged: (value) => _save(
                          preferences.copyWith(
                            maxDailySuggestions: value.round(),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: preferences.quietHoursEnabled,
                      onChanged: (value) => _save(
                        preferences.copyWith(quietHoursEnabled: value),
                      ),
                      secondary: const Icon(Icons.bedtime_outlined),
                      title: const Text('Quiet hours'),
                      subtitle: const Text(
                          'Suppress proactive cards during your chosen window.'),
                    ),
                    if (preferences.quietHoursEnabled)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: _HourPicker(
                                label: 'Start',
                                value: preferences.quietHoursStart,
                                onChanged: (value) => _save(
                                  preferences.copyWith(quietHoursStart: value),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _HourPicker(
                                label: 'End',
                                value: preferences.quietHoursEnd,
                                onChanged: (value) => _save(
                                  preferences.copyWith(quietHoursEnd: value),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Decision receipts',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (records.isNotEmpty)
                    TextButton(
                      onPressed: _confirmClearHistory,
                      child: const Text('Clear'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (records.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.receipt_long_outlined),
                    title: Text('No decisions yet'),
                    subtitle: Text(
                      'Receipts appear here after the local specialists evaluate an opportunity.',
                    ),
                  ),
                )
              else
                ...records.map((record) => _ReceiptTile(record: record)),
              const SizedBox(height: 16),
              Text(
                'Capability boundary',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Card(
                child: Column(
                  children: _registry.all
                      .map(
                        (capability) => ListTile(
                          leading: Icon(_riskIcon(capability.risk)),
                          title: Text(capability.title),
                          subtitle: Text(
                            '${capability.risk.name} • '
                            '${_approvalLabel(capability.approvalMode)}',
                          ),
                          trailing: capability.hasExternalSideEffect
                              ? const Tooltip(
                                  message: 'External side effect',
                                  child: Icon(Icons.open_in_new, size: 18),
                                )
                              : null,
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static IconData _riskIcon(NeuraCapabilityRisk risk) => switch (risk) {
        NeuraCapabilityRisk.readOnly => Icons.visibility_outlined,
        NeuraCapabilityRisk.reversibleLocal => Icons.undo_outlined,
        NeuraCapabilityRisk.sensitiveLocal => Icons.lock_outline,
        NeuraCapabilityRisk.external => Icons.open_in_new,
        NeuraCapabilityRisk.critical => Icons.block,
      };

  static String _approvalLabel(NeuraApprovalMode mode) => switch (mode) {
        NeuraApprovalMode.none => 'user gesture',
        NeuraApprovalMode.session => 'session approval',
        NeuraApprovalMode.everyTime => 'approve every time',
        NeuraApprovalMode.blocked => 'blocked',
      };
}

class _ReceiptTile extends StatelessWidget {
  const _ReceiptTile({required this.record});

  final NeuraIntelligenceRecord record;

  @override
  Widget build(BuildContext context) {
    final receipt = record.receipt;
    return Card(
      child: ExpansionTile(
        leading: Icon(
          receipt.isVisible
              ? Icons.check_circle_outline
              : Icons.shield_outlined,
        ),
        title: Text(record.title),
        subtitle: Text(
          '${receipt.outcome.name} • ${(receipt.score * 100).round()}% • '
          '${_formatTime(receipt.evaluatedAt)}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (record.body.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(record.body),
            ),
          const SizedBox(height: 8),
          ...receipt.reasons.map(
            (reason) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.arrow_right, size: 18),
              title: Text(reason),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Outcome: ${receipt.userOutcome.name} • '
              '${receipt.evidenceIds.length} evidence references',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} $hour:$minute';
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
          value: value,
          isExpanded: true,
          items: List.generate(
            24,
            (hour) => DropdownMenuItem(
              value: hour,
              child: Text('${hour.toString().padLeft(2, '0')}:00'),
            ),
          ),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}
