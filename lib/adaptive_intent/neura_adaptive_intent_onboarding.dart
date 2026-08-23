import 'dart:async';

import 'package:flutter/material.dart';

import 'neura_adaptive_intent_preferences.dart';
import 'neura_adaptive_intent_runtime.dart';

class NeuraAdaptiveIntentOnboardingScreen extends StatefulWidget {
  const NeuraAdaptiveIntentOnboardingScreen({
    this.preferencesController,
    this.runtime,
    super.key,
  });

  final NeuraAdaptiveIntentPreferencesController? preferencesController;
  final NeuraAdaptiveIntentRuntime? runtime;

  @override
  State<NeuraAdaptiveIntentOnboardingScreen> createState() =>
      _NeuraAdaptiveIntentOnboardingScreenState();
}

class _NeuraAdaptiveIntentOnboardingScreenState
    extends State<NeuraAdaptiveIntentOnboardingScreen> {
  late final NeuraAdaptiveIntentPreferencesController _preferences;
  late final NeuraAdaptiveIntentRuntime _runtime;

  bool _loading = true;
  bool _saving = false;
  Object? _error;
  bool _useMood = true;
  bool _useFocus = true;
  bool _useQuests = true;
  bool _useActivity = true;

  @override
  void initState() {
    super.initState();
    _preferences =
        widget.preferencesController ??
        NeuraAdaptiveIntentPreferencesController.instance;
    _runtime = widget.runtime ?? NeuraAdaptiveIntentRuntime.instance;
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _preferences.initialize();
      final current = _preferences.preferences;
      if (!mounted) return;
      setState(() {
        _useMood = current.useMoodSignal;
        _useFocus = current.useFocusSignal;
        _useQuests = current.useQuestSignal;
        _useActivity = current.useActivitySignal;
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

  Future<void> _enable() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _preferences.completeOnboarding(
        useMoodSignal: _useMood,
        useFocusSignal: _useFocus,
        useQuestSignal: _useQuests,
        useActivitySignal: _useActivity,
      );
      await _runtime.initialize();
      await _runtime.refreshLiveSignals();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  Future<void> _disable() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _preferences.setEnabled(false);
      if (_runtime.session != null) {
        _runtime.discardSession(userGesture: true);
      }
      if (!mounted) return;
      Navigator.of(context).pop(false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up Adaptive Intent')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                            const Icon(Icons.psychology_alt_outlined),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'A local adaptive planning layer',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Neura estimates practical available attention and '
                          'changes plan size, information density, and consent '
                          'requirements. It does not diagnose a condition.',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Your choices remain visible and reversible. You can '
                          'disable Adaptive Intent or erase its local data at '
                          'any time.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.lock_outline),
                        title: Text('Private by design'),
                        subtitle: Text(
                          'Raw mood notes, journals, therapy text, dreams, '
                          'messages, and memory content are not used as signals.',
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _useMood,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _useMood = value),
                        secondary: const Icon(Icons.favorite_outline),
                        title: const Text('Recent mood score'),
                        subtitle: const Text(
                          'Uses only the 0–10 score and timestamp, never its note.',
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _useFocus,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _useFocus = value),
                        secondary: const Icon(Icons.center_focus_strong),
                        title: const Text('Selected Focus Mode'),
                        subtitle: const Text(
                          'Uses the mode you explicitly selected in Neura.',
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _useQuests,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _useQuests = value),
                        secondary: const Icon(Icons.flag_outlined),
                        title: const Text('Quest momentum'),
                        subtitle: const Text(
                          'Uses active and recently completed quest counts only.',
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _useActivity,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _useActivity = value),
                        secondary: const Icon(Icons.swap_horiz),
                        title: const Text('In-app switching and interruptions'),
                        subtitle: const Text(
                          'Uses bounded event counts from inside Neura only.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.verified_user_outlined),
                    title: Text('First executable action'),
                    subtitle: Text(
                      'Adaptive Intent may prepare one reversible local quest. '
                      'Action Loom still requires fresh review and approval, '
                      'and provides undo. Messages, purchases, calendars, '
                      'money, and cloud actions remain blocked.',
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: const ListTile(
                      leading: Icon(Icons.error_outline),
                      title: Text(
                        'Adaptive Intent could not save these choices.',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  key: const ValueKey('adaptive-intent-enable'),
                  onPressed: _saving ? null : () => unawaited(_enable()),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    _saving
                        ? 'Saving…'
                        : _preferences.enabled
                        ? 'Save signal choices'
                        : 'Enable Adaptive Intent',
                  ),
                ),
                const SizedBox(height: 8),
                if (_preferences.enabled)
                  OutlinedButton.icon(
                    key: const ValueKey('adaptive-intent-disable'),
                    onPressed: _saving ? null : () => unawaited(_disable()),
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Turn off Adaptive Intent'),
                  )
                else
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Not now'),
                  ),
              ],
            ),
    );
  }
}
