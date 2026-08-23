import 'dart:async';

import 'package:flutter/material.dart';

import 'neura_adaptive_intent_onboarding.dart';
import 'neura_adaptive_intent_preferences.dart';
import 'neura_adaptive_intent_runtime.dart';
import 'neura_adaptive_intent_screen.dart';

class NeuraAdaptiveIntentEntryScreen extends StatefulWidget {
  const NeuraAdaptiveIntentEntryScreen({super.key});

  @override
  State<NeuraAdaptiveIntentEntryScreen> createState() =>
      _NeuraAdaptiveIntentEntryScreenState();
}

class _NeuraAdaptiveIntentEntryScreenState
    extends State<NeuraAdaptiveIntentEntryScreen> {
  final _runtime = NeuraAdaptiveIntentRuntime.instance;
  final _preferences = NeuraAdaptiveIntentPreferencesController.instance;

  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _runtime.initialize();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
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
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Adaptive Intent OS')),
        body: Center(
          child: FilledButton.icon(
            onPressed: () {
              setState(() => _loading = true);
              unawaited(_initialize());
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Retry local initialization'),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _preferences,
      builder: (context, _) {
        if (!_runtime.featureEnabled) {
          return NeuraAdaptiveIntentOnboardingScreen(
            preferencesController: _preferences,
            runtime: _runtime,
          );
        }
        return const NeuraAdaptiveIntentScreen();
      },
    );
  }
}
