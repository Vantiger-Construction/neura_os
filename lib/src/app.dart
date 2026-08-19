import 'package:flutter/material.dart';

import '../modules/core/error_handler.dart';
import '../modules/human/human_prefs.dart';
import '../modules/human/human_prefs_controller.dart';
import '../startup/neura_boot_screen.dart';
import '../theme/app_theme.dart';
import 'shell/neura_shell.dart';
import '../neura_shell/neura_shell_root.dart';

class NeuroCompanionApp extends StatelessWidget {
  const NeuroCompanionApp({super.key});

  /// NeuraShellOverlay wraps MaterialApp's Navigator from outside (via
  /// MaterialApp.builder), so any context captured inside NeuraShellOverlay
  /// can never resolve Navigator.of(context) — the Navigator is a descendant,
  /// not an ancestor, of that context. This key gives call sites like
  /// NeuraRoomSelectorSheet a context that's actually inside the Navigator.
  static final navigatorKey = GlobalKey<NavigatorState>();

  static ThemeMode _themeModeFor(NeuraThemePref pref) {
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
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Neura OS',
          themeMode: _themeModeFor(prefs.theme),
          theme: AppTheme.light(highContrast: prefs.highContrast),
          darkTheme: AppTheme.dark(highContrast: prefs.highContrast),
          scaffoldMessengerKey: ErrorHandler.scaffoldMessengerKey,
          builder: (context, child) {
            return NeuraShellRoot(
              child: NeuraAmbientShell(child: child ?? const SizedBox.shrink()),
            );
          },
          // NeuraBootScreen owns startup sequencing and fades into EnhancedNavigation.
          home: const NeuraBootScreen(),
        );
      },
    );
  }
}
