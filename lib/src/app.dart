import 'package:flutter/material.dart';

import '../modules/core/error_handler.dart';
import '../startup/neura_boot_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Neura OS',
      theme: ThemeData.dark(),
      scaffoldMessengerKey: ErrorHandler.scaffoldMessengerKey,
      builder: (context, child) {
        return NeuraShellRoot(
          child: NeuraAmbientShell(child: child ?? const SizedBox.shrink()),
        );
      },
      // NeuraBootScreen owns startup sequencing and fades into EnhancedNavigation.
      home: const NeuraBootScreen(),
    );
  }
}
