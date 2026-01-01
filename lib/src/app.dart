import 'package:flutter/material.dart';

import '../modules/core/error_handler.dart';
import '../modules/human/human_prefs.dart';
import '../modules/human/human_prefs_controller.dart';
import '../modules/navigation/enhanced_navigation.dart';
import 'shell/neura_shell.dart' as shell;
import '../neura_shell/neura_shell_root.dart';

class NeuroCompanionApp extends StatelessWidget {
  const NeuroCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HumanPrefs>(
      valueListenable: HumanPrefsController.instance.prefs,
      builder: (context, prefs, _) {
        final themeMode = switch (prefs.theme) {
          NeuraThemePref.dark => ThemeMode.dark,
          NeuraThemePref.light => ThemeMode.light,
          NeuraThemePref.system => ThemeMode.system,
        };

        final baseDark = ThemeData.dark();
        final baseLight = ThemeData.light();

        final darkTheme = prefs.highContrast
            ? baseDark.copyWith(
                colorScheme: baseDark.colorScheme.copyWith(
                  primary: Colors.cyanAccent,
                  secondary: Colors.amberAccent,
                ),
              )
            : baseDark;

        final lightTheme = prefs.highContrast
            ? baseLight.copyWith(
                colorScheme: baseLight.colorScheme.copyWith(
                  primary: Colors.blue,
                  secondary: Colors.deepOrange,
                ),
              )
            : baseLight;

        return MaterialApp(
          title: 'Neura OS',
          themeMode: themeMode,
          theme: lightTheme,
          darkTheme: darkTheme,
          scaffoldMessengerKey: ErrorHandler.scaffoldMessengerKey,
          builder: (context, child) {
            final c = child ?? const SizedBox.shrink();
            final mq = MediaQuery.of(context);
            final scaled = mq.copyWith(textScaler: TextScaler.linear(prefs.textScale));

            // Global shell layers:
            // 1) Rooms + avatar overlay (NeuraShellRoot)
            // 2) Ambient FX + Focus banner (src/shell)
            return MediaQuery(
              data: scaled,
              child: NeuraShellRoot(child: shell.NeuraShell(child: c)),
            );
          },
          home: const EnhancedNavigation(),
        );
      },
    );
  }
}
