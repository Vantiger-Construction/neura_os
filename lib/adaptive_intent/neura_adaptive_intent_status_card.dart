import 'dart:async';

import 'package:flutter/material.dart';

import '../cognitive/neura_cognitive_state.dart';
import '../intent_compiler/neura_action_graph.dart';
import 'neura_adaptive_intent_controller.dart';
import 'neura_adaptive_intent_onboarding.dart';
import 'neura_adaptive_intent_preferences.dart';
import 'neura_adaptive_intent_runtime.dart';
import 'neura_adaptive_intent_screen.dart';
import 'neura_adaptive_plan_session.dart';
import 'neura_adaptive_session_screen.dart';

class NeuraAdaptiveIntentStatusCard extends StatefulWidget {
  const NeuraAdaptiveIntentStatusCard({super.key});

  @override
  State<NeuraAdaptiveIntentStatusCard> createState() =>
      _NeuraAdaptiveIntentStatusCardState();
}

class _NeuraAdaptiveIntentStatusCardState
    extends State<NeuraAdaptiveIntentStatusCard> {
  final _controller = NeuraAdaptiveIntentController.instance;
  final _runtime = NeuraAdaptiveIntentRuntime.instance;
  final _preferences = NeuraAdaptiveIntentPreferencesController.instance;
  Object? _initializationError;

  @override
  void initState() {
    super.initState();
    _runtime.recordSurfaceVisit('dashboard');
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _runtime.initialize();
      if (mounted) {
        setState(() => _initializationError = null);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _initializationError = error);
      }
    }
  }

  Future<void> _openOnboarding() async {
    final enabled = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const NeuraAdaptiveIntentOnboardingScreen(),
      ),
    );
    if (enabled == true) {
      await _runtime.refreshLiveSignals();
    }
  }

  void _openPrimary() {
    if (!_runtime.featureEnabled) {
      unawaited(_openOnboarding());
      return;
    }
    _runtime.recordSurfaceVisit('adaptive_intent_center');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NeuraAdaptiveIntentScreen(),
      ),
    );
  }

  void _openSession() {
    if (!_runtime.featureEnabled) {
      unawaited(_openOnboarding());
      return;
    }
    _runtime.recordSurfaceVisit('adaptive_session');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NeuraAdaptiveSessionScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _preferences,
      builder: (context, _) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => AnimatedBuilder(
          animation: _runtime,
          builder: (context, _) {
            final state = _controller.state;
            final session = _runtime.session;
            final enabled = _runtime.featureEnabled;
            final initializationFailed = _initializationError != null &&
                (!_controller.initialized || !_preferences.initialized);
            final localProgress = session?.progress.where(
              (item) => !item.step.blocked && !item.step.effect.isExternal,
            );
            final completed = localProgress
                ?.where(
                  (item) => item.status == NeuraPlanStepStatus.completed,
                )
                .length;
            final total = localProgress?.length;

            final subtitle = initializationFailed
                ? 'Local settings could not be loaded. Tap to retry.'
                : !enabled
                    ? 'Off by default • choose exactly which local signals Neura may use'
                    : session != null
                        ? '$completed of $total local steps completed'
                        : '${(state.availableBandwidth * 100).round()}% '
                            'available bandwidth • '
                            '${_controller.interfacePolicy.maxPrimaryActions} '
                            'primary action'
                            '${_controller.interfacePolicy.maxPrimaryActions == 1 ? '' : 's'}';

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: initializationFailed
                            ? () => unawaited(_initialize())
                            : _openPrimary,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                enabled
                                    ? _modeIcon(state.mode)
                                    : Icons.psychology_alt_outlined,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            enabled
                                                ? 'Adaptive Intent • ${state.mode.label}'
                                                : 'Adaptive Intent beta',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                        ),
                                        if (_controller.safeMode)
                                          const Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text('Safe Mode'),
                                          )
                                        else if (!enabled)
                                          const Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text('Off'),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      subtitle,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      !enabled
                                          ? 'Local-only planning, explainable receipts, and one reversible quest after fresh approval.'
                                          : session != null
                                              ? 'One local plan is active. External steps remain review-only.'
                                              : state.mode.summary,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Adaptive Intent privacy and signal settings',
                      onPressed: initializationFailed
                          ? () => unawaited(_initialize())
                          : () => unawaited(_openOnboarding()),
                      icon: const Icon(Icons.tune),
                    ),
                    IconButton(
                      tooltip: !enabled
                          ? 'Set up Adaptive Intent'
                          : session == null
                              ? 'Start a local plan session'
                              : 'Open active plan session',
                      onPressed: initializationFailed
                          ? () => unawaited(_initialize())
                          : _openSession,
                      icon: Icon(
                        !enabled
                            ? Icons.playlist_add_check_circle_outlined
                            : session == null
                                ? Icons.playlist_add_check_circle_outlined
                                : Icons.play_circle_outline,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
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
