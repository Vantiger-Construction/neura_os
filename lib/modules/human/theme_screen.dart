import 'package:flutter/material.dart';

import 'human_prefs.dart';
import 'human_prefs_controller.dart';

class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  ThemeMode _toThemeMode(NeuraThemePref pref) {
    switch (pref) {
      case NeuraThemePref.dark:
        return ThemeMode.dark;
      case NeuraThemePref.light:
        return ThemeMode.light;
      case NeuraThemePref.system:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HumanPrefs>(
      valueListenable: HumanPrefsController.instance.prefs,
      builder: (context, prefs, _) {
        final themeMode = _toThemeMode(prefs.theme);
        return Scaffold(
          appBar: AppBar(title: const Text('Themes')),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const ListTile(
                title: Text('Theme mode'),
                subtitle: Text('Choose what your eyes want today.'),
              ),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.settings_brightness_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                ],
                selected: <ThemeMode>{themeMode},
                onSelectionChanged: (selection) {
                  final selected = selection.first;
                  final pref = switch (selected) {
                    ThemeMode.dark => NeuraThemePref.dark,
                    ThemeMode.light => NeuraThemePref.light,
                    _ => NeuraThemePref.system,
                  };
                  HumanPrefsController.instance
                      .update(prefs.copyWith(theme: pref));
                },
              ),
              const Divider(),
              SwitchListTile(
                value: prefs.highContrast,
                onChanged: (v) => HumanPrefsController.instance
                    .update(prefs.copyWith(highContrast: v)),
                title: const Text('High contrast'),
                subtitle: const Text('Sharper separation between UI elements.'),
                secondary: const Icon(Icons.contrast_outlined),
              ),
              SwitchListTile(
                value: prefs.lowStim,
                onChanged: (v) => HumanPrefsController.instance
                    .update(prefs.copyWith(lowStim: v)),
                title: const Text('Low-stimulation mode'),
                subtitle: const Text('Turns down visual intensity and glow.'),
                secondary: const Icon(Icons.nights_stay_outlined),
              ),
            ],
          ),
        );
      },
    );
  }
}
