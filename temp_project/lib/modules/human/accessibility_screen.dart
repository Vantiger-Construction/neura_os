import 'package:flutter/material.dart';

import 'human_prefs.dart';
import 'human_prefs_controller.dart';
import '../../src/shell/shell_prefs.dart';

class AccessibilityScreen extends StatelessWidget {
  const AccessibilityScreen({super.key});

  Future<void> _applySafeMode(bool enabled, HumanPrefs prefs) async {
    // Safe Mode is the "make it calm and predictable" big red button.
    // We force low-stim + reduced motion, and we hard-disable shell FX so nothing surprises the user.
    final next = enabled
        ? prefs.copyWith(
            safeMode: true,
            reducedMotion: true,
            lowStim: true,
          )
        : prefs.copyWith(safeMode: false);

    await HumanPrefsController.instance.update(next);

    if (enabled) {
      final sp = ShellPrefsController.instance.prefs.value;
      await ShellPrefsController.instance.update(
        sp.copyWith(
          ambientFx: false,
          portalFx: false,
          walkingShimmer: false,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HumanPrefs>(
      valueListenable: HumanPrefsController.instance.prefs,
      builder: (context, prefs, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Accessibility')),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const ListTile(
                title: Text('Comfort controls'),
                subtitle: Text('Tune motion + readability so your brain can do the hard part.'),
              ),
              SwitchListTile(
                value: prefs.safeMode,
                onChanged: (v) => _applySafeMode(v, prefs),
                title: const Text('Safe Mode'),
                subtitle: const Text('One switch to reduce stimulation + disable fancy FX.'),
                secondary: const Icon(Icons.shield_outlined),
              ),
              SwitchListTile(
                value: prefs.lowStim,
                onChanged: prefs.safeMode ? null : (v) => HumanPrefsController.instance.update(prefs.copyWith(lowStim: v)),
                title: const Text('Low-stimulation mode'),
                subtitle: const Text('Dials back glow, shimmer, and visual noise.'),
                secondary: const Icon(Icons.blur_off_outlined),
              ),
              SwitchListTile(
                value: prefs.reducedMotion,
                onChanged: prefs.safeMode ? null : (v) => HumanPrefsController.instance.update(prefs.copyWith(reducedMotion: v)),
                title: const Text('Reduce motion'),
                subtitle: const Text('Disables ambient animations and soft transitions.'),
                secondary: const Icon(Icons.motion_photos_off_outlined),
              ),
              SwitchListTile(
                value: prefs.highContrast,
                onChanged: (v) => HumanPrefsController.instance.update(prefs.copyWith(highContrast: v)),
                title: const Text('High contrast'),
                subtitle: const Text('Improves readability and UI contrast.'),
                secondary: const Icon(Icons.contrast_outlined),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.text_fields),
                title: const Text('Text size'),
                subtitle: Text('Scale: ${prefs.textScale.toStringAsFixed(2)}x'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Slider(
                  min: 0.85,
                  max: 1.35,
                  divisions: 10,
                  value: prefs.textScale,
                  onChanged: (v) => HumanPrefsController.instance.update(prefs.copyWith(textScale: v)),
                ),
              ),
              const Divider(),
              SwitchListTile(
                value: prefs.allowLearning,
                onChanged: (v) => HumanPrefsController.instance.update(prefs.copyWith(allowLearning: v)),
                title: const Text('Allow local learning'),
                subtitle: const Text('Let Neura remember what helps (stored on-device only).'),
                secondary: const Icon(Icons.school_outlined),
              ),
            ],
          ),
        );
      },
    );
  }
}
