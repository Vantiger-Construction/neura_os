import 'dart:async';

import 'package:flutter/material.dart';

import '../cognitive/neura_cognitive_state.dart';
import 'neura_adaptive_intent_controller.dart';
import 'neura_adaptive_intent_screen.dart';

class NeuraAdaptiveIntentStatusCard extends StatefulWidget {
  const NeuraAdaptiveIntentStatusCard({super.key});

  @override
  State<NeuraAdaptiveIntentStatusCard> createState() =>
      _NeuraAdaptiveIntentStatusCardState();
}

class _NeuraAdaptiveIntentStatusCardState
    extends State<NeuraAdaptiveIntentStatusCard> {
  final _controller = NeuraAdaptiveIntentController.instance;
  Object? _initializationError;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (mounted) {
        setState(() => _initializationError = null);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _initializationError = error);
      }
    }
  }

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NeuraAdaptiveIntentScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final state = _controller.state;
        final initializationFailed =
            _initializationError != null && !_controller.initialized;
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _open,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_modeIcon(state.mode)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Adaptive Intent • ${state.mode.label}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (_controller.safeMode)
                              const Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text('Safe Mode'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          initializationFailed
                              ? 'Local settings could not be loaded. Tap to retry.'
                              : '${(state.availableBandwidth * 100).round()}% '
                                    'available bandwidth • '
                                    '${_controller.interfacePolicy.maxPrimaryActions} '
                                    'primary action'
                                    '${_controller.interfacePolicy.maxPrimaryActions == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          state.mode.summary,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

IconData _modeIcon(NeuraBandwidthMode mode) {
  return switch (mode) {
    NeuraBandwidthMode.recovery => Icons.spa_outlined,
    NeuraBandwidthMode.simplified => Icons.filter_3_outlined,
    NeuraBandwidthMode.balanced => Icons.balance_outlined,
    NeuraBandwidthMode.deepFocus => Icons.center_focus_strong,
  };
}
