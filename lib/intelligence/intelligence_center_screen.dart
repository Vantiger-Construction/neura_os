import 'dart:async';

import 'package:flutter/material.dart';

import '../reliability/safe_boot.dart';
import 'capability_registry.dart';
import 'intelligence_preferences.dart';
import 'models.dart';
import 'neura_intelligence_controller.dart';

const String _kAllSpecialists = 'All';
const String _kAllOutcomes = 'All';

enum _ReceiptRange { all, day, week, month }

class NeuraIntelligenceCenterScreen extends StatefulWidget {
  const NeuraIntelligenceCenterScreen({super.key, this.initialReceiptId});

  /// When set (typically reached from a Timeline Vault entry in Diagnostics),
  /// the receipt list opens filtered to this one receipt instead of the
  /// default recent list.
  final String? initialReceiptId;

  @override
  State<NeuraIntelligenceCenterScreen> createState() =>
      _NeuraIntelligenceCenterScreenState();
}

class _NeuraIntelligenceCenterScreenState
    extends State<NeuraIntelligenceCenterScreen> {
  final _controller = NeuraIntelligenceController.instance;
  final _registry = NeuraCapabilityRegistry();

  String? _pinnedReceiptId;
  String _specialistFilter = _kAllSpecialists;
  String _outcomeFilter = _kAllOutcomes;
  _ReceiptRange _rangeFilter = _ReceiptRange.all;

  @override
  void initState() {
    super.initState();
    _pinnedReceiptId = widget.initialReceiptId;
    unawaited(_controller.initialize().catchError((_) {}));
  }

  void _clearPinnedReceipt() => setState(() => _pinnedReceiptId = null);

  List<NeuraIntelligenceRecord> _applyFilters(
    List<NeuraIntelligenceRecord> records,
    DateTime now,
  ) {
    if (_pinnedReceiptId != null) {
      return records
          .where((item) => item.receipt.id == _pinnedReceiptId)
          .toList(growable: false);
    }
    final cutoff = switch (_rangeFilter) {
      _ReceiptRange.all => null,
      _ReceiptRange.day => now.subtract(const Duration(days: 1)),
      _ReceiptRange.week => now.subtract(const Duration(days: 7)),
      _ReceiptRange.month => now.subtract(const Duration(days: 30)),
    };
    return records
        .where((item) {
          if (_specialistFilter != _kAllSpecialists &&
              item.receipt.specialistId != _specialistFilter) {
            return false;
          }
          if (_outcomeFilter != _kAllOutcomes &&
              item.receipt.userOutcome.name != _outcomeFilter) {
            return false;
          }
          if (cutoff != null && item.receipt.evaluatedAt.isBefore(cutoff)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  static String _specialistLabel(String specialistId) {
    final tail = specialistId.contains('.')
        ? specialistId.substring(specialistId.lastIndexOf('.') + 1)
        : specialistId;
    final words = tail.split('_').where((word) => word.isNotEmpty);
    if (words.isEmpty) return specialistId;
    final label = words.join(' ');
    return label[0].toUpperCase() + label.substring(1);
  }

  void _save(NeuraIntelligencePreferences preferences) {
    unawaited(
      _controller.updatePreferences(preferences).catchError((Object error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not save intelligence settings.'),
            ),
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
          final now = DateTime.now();
          final allRecords = _controller.records.reversed.toList();
          final specialistIds =
              allRecords
                  .map((item) => item.receipt.specialistId)
                  .toSet()
                  .toList()
                ..sort();
          final records = _applyFilters(allRecords, now).take(50).toList();
          final paused =
              preferences.pausedUntil != null &&
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
                                    : preferences.allowsProactiveSuggestions
                                    ? '${preferences.proactivityLevel.label} · on-device'
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
                    ListTile(
                      leading: const Icon(Icons.auto_awesome_outlined),
                      title: const Text('Proactive intelligence'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          Text(preferences.proactivityLevel.description),
                          const SizedBox(height: 10),
                          SegmentedButton<NeuraProactivityLevel>(
                            segments: NeuraProactivityLevel.values
                                .map(
                                  (level) => ButtonSegment(
                                    value: level,
                                    label: Text(level.label),
                                  ),
                                )
                                .toList(growable: false),
                            selected: {preferences.proactivityLevel},
                            onSelectionChanged: (selection) {
                              final level = selection.single;
                              _save(
                                preferences.copyWith(
                                  enabled: level != NeuraProactivityLevel.off,
                                  proactivityLevel: level,
                                ),
                              );
                            },
                          ),
                        ],
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
                        'Expose score, evidence count, and policy reasons.',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.notifications_paused_outlined),
                      title: Text(
                        'Personal daily cap: '
                        '${preferences.maxDailySuggestions}',
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Slider(
                            value: preferences.maxDailySuggestions.toDouble(),
                            min: 1,
                            max: 6,
                            divisions: 5,
                            label: preferences.maxDailySuggestions.toString(),
                            onChanged: preferences.allowsProactiveSuggestions
                                ? (value) => _save(
                                    preferences.copyWith(
                                      maxDailySuggestions: value.round(),
                                    ),
                                  )
                                : null,
                          ),
                          Text(
                            'The ${preferences.proactivityLevel.label.toLowerCase()} '
                            'level currently limits this to '
                            '${preferences.effectiveMaxDailySuggestions} per day.',
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: preferences.quietHoursEnabled,
                      onChanged: (value) =>
                          _save(preferences.copyWith(quietHoursEnabled: value)),
                      secondary: const Icon(Icons.bedtime_outlined),
                      title: const Text('Quiet hours'),
                      subtitle: const Text(
                        'Suppress proactive cards during your chosen window.',
                      ),
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
                  if (allRecords.isNotEmpty && _pinnedReceiptId == null)
                    TextButton(
                      onPressed: _confirmClearHistory,
                      child: const Text('Clear'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (_pinnedReceiptId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InputChip(
                    avatar: const Icon(Icons.link, size: 18),
                    label: const Text('Opened from Timeline Vault'),
                    onDeleted: _clearPinnedReceipt,
                    deleteIcon: const Icon(Icons.close),
                  ),
                )
              else if (allRecords.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DropdownButton<String>(
                        value: _specialistFilter,
                        items: [_kAllSpecialists, ...specialistIds]
                            .map(
                              (id) => DropdownMenuItem(
                                value: id,
                                child: Text(
                                  id == _kAllSpecialists
                                      ? 'All specialists'
                                      : _specialistLabel(id),
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) => setState(
                          () => _specialistFilter = value ?? _kAllSpecialists,
                        ),
                      ),
                      DropdownButton<String>(
                        value: _outcomeFilter,
                        items:
                            [
                                  _kAllOutcomes,
                                  ...NeuraSuggestionOutcome.values.map(
                                    (o) => o.name,
                                  ),
                                ]
                                .map(
                                  (name) => DropdownMenuItem(
                                    value: name,
                                    child: Text(
                                      name == _kAllOutcomes
                                          ? 'All outcomes'
                                          : name,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                        onChanged: (value) => setState(
                          () => _outcomeFilter = value ?? _kAllOutcomes,
                        ),
                      ),
                      DropdownButton<_ReceiptRange>(
                        value: _rangeFilter,
                        items: const [
                          DropdownMenuItem(
                            value: _ReceiptRange.all,
                            child: Text('All time'),
                          ),
                          DropdownMenuItem(
                            value: _ReceiptRange.day,
                            child: Text('Last 24 hours'),
                          ),
                          DropdownMenuItem(
                            value: _ReceiptRange.week,
                            child: Text('Last 7 days'),
                          ),
                          DropdownMenuItem(
                            value: _ReceiptRange.month,
                            child: Text('Last 30 days'),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _rangeFilter = value ?? _ReceiptRange.all,
                        ),
                      ),
                    ],
                  ),
                ),
              if (records.isEmpty)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(
                      allRecords.isEmpty
                          ? 'No decisions yet'
                          : 'No receipts match this filter',
                    ),
                    subtitle: Text(
                      allRecords.isEmpty
                          ? 'Receipts appear here after the local specialists evaluate an opportunity.'
                          : 'Try a wider time range or a different specialist.',
                    ),
                  ),
                )
              else
                ...records.map(
                  (record) => _ReceiptTile(
                    record: record,
                    highlighted: record.receipt.id == _pinnedReceiptId,
                    specialistLabel: _specialistLabel(
                      record.receipt.specialistId,
                    ),
                    specialistReputation: _controller.specialistReputation(
                      record.receipt.specialistId,
                    ),
                  ),
                ),
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
  const _ReceiptTile({
    required this.record,
    this.highlighted = false,
    required this.specialistLabel,
    required this.specialistReputation,
  });

  final NeuraIntelligenceRecord record;
  final bool highlighted;
  final String specialistLabel;
  final double specialistReputation;

  @override
  Widget build(BuildContext context) {
    final receipt = record.receipt;
    return Card(
      color: highlighted
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      child: ExpansionTile(
        initiallyExpanded: highlighted,
        leading: Icon(
          receipt.isVisible
              ? Icons.check_circle_outline
              : Icons.shield_outlined,
        ),
        title: Text(record.title),
        subtitle: Text(
          '$specialistLabel • ${receipt.outcome.name} • '
          '${(receipt.score * 100).round()}% • '
          '${_formatTime(receipt.evaluatedAt)}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (record.body.isNotEmpty)
            Align(alignment: Alignment.centerLeft, child: Text(record.body)),
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
              '${receipt.evidenceIds.length} evidence references • '
              'Specialist track record: ${(specialistReputation * 100).round()}%',
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
