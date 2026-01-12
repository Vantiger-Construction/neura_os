import 'package:flutter/material.dart';

import '../modules/core/error_handler.dart';
import '../modules/navigation/enhanced_navigation.dart';
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
      home: const EnhancedNavigation(),
    );
  }
}
