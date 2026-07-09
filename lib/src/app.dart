import 'package:flutter/material.dart';

import '../modules/core/error_handler.dart';
import '../startup/neura_boot_screen.dart';
import 'shell/neura_shell.dart';
import '../neura_shell/neura_shell_root.dart';

class NeuroCompanionApp extends StatelessWidget {
  const NeuroCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neura OS',
      theme: ThemeData.dark(),
      scaffoldMessengerKey: ErrorHandler.scaffoldMessengerKey,
      builder: (context, child) {
        return NeuraShellRoot(
          child: NeuraShell(child: child ?? const SizedBox.shrink()),
        );
      },
      // NeuraBootScreen owns startup sequencing and fades into EnhancedNavigation.
      home: const NeuraBootScreen(),
    );
  }
}
