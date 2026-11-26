import 'package:flutter/material.dart';

import '../reliability/safe_boot.dart';

/// A visible mode choice that keeps recovery latched until a fresh process.
class NeuraSafeModeSwitch extends StatefulWidget {
  const NeuraSafeModeSwitch({super.key});

  @override
  State<NeuraSafeModeSwitch> createState() => _NeuraSafeModeSwitchState();
}

class _NeuraSafeModeSwitchState extends State<NeuraSafeModeSwitch> {
  bool _saving = false;

  Future<void> _setSafeMode(bool enabled) async {
    final boot = SafeBoot.instance;
    if (_saving || boot.restartRequired.value) return;
    setState(() => _saving = true);
    try {
      if (enabled) {
        await boot.requestSafeMode();
      } else {
        await boot.clearSafeMode();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The mode change could not be saved. '
              'Safe Mode remains active.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final boot = SafeBoot.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([boot.safeMode, boot.restartRequired]),
      builder: (context, _) {
        final safeMode = boot.safeMode.value;
        final restartRequired = boot.restartRequired.value;
        return SwitchListTile(
          key: const Key('safe-mode-switch'),
          secondary: Icon(safeMode
              ? Icons.health_and_safety_outlined
              : Icons.verified_outlined),
          title: const Text('Safe Mode'),
          subtitle: Text(restartRequired
              ? 'Restart Neura to finish turning Safe Mode off. '
                  'Microphone and speech stay paused until then.'
              : safeMode
                  ? 'On. Microphone, speech and cloud services are paused.'
                  : 'Off. Normal voice and sound settings apply.'),
          value: safeMode && !restartRequired,
          onChanged: _saving || restartRequired ? null : _setSafeMode,
        );
      },
    );
  }
}
