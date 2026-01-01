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
              RadioListTile<ThemeMode>(
                value: ThemeMode.system,
                groupValue: themeMode,
                onChanged: (_) => HumanPrefsController.instance.update(
                  prefs.copyWith(theme: NeuraThemePref.system),
                ),
                title: const Text('System'),
                secondary: const Icon(Icons.settings_brightness_outlined),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.dark,
                groupValue: themeMode,
                onChanged: (_) => HumanPrefsController.instance.update(
                  prefs.copyWith(theme: NeuraThemePref.dark),
                ),
                title: const Text('Dark'),
                secondary: const Icon(Icons.dark_mode_outlined),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.light,
                groupValue: themeMode,
                onChanged: (_) => HumanPrefsController.instance.update(
                  prefs.copyWith(theme: NeuraThemePref.light),
                ),
                title: const Text('Light'),
                secondary: const Icon(Icons.light_mode_outlined),
              ),
              const Divider(),
              SwitchListTile(
                value: prefs.highContrast,
                onChanged: (v) => HumanPrefsController.instance.update(prefs.copyWith(highContrast: v)),
                title: const Text('High contrast'),
                subtitle: const Text('Sharper separation between UI elements.'),
                secondary: const Icon(Icons.contrast_outlined),
              ),
              SwitchListTile(
                value: prefs.lowStim,
                onChanged: (v) => HumanPrefsController.instance.update(prefs.copyWith(lowStim: v)),
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
