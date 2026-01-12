import 'package:flutter/material.dart';

import '../modules/core/error_handler.dart';
import '../modules/navigation/enhanced_navigation.dart';
import 'shell/neura_shell.dart';
import 'neura/neura_global_overlay.dart';

class NeuroCompanionApp extends StatelessWidget {
  const NeuroCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neura OS',
      theme: ThemeData.dark(),
      scaffoldMessengerKey: ErrorHandler.scaffoldMessengerKey,
      builder: (context, child) {
        // Wrap the entire shell in a global overlay which wires Neura's
        // event bus, memory and return messages.
        return NeuraGlobalOverlay(
          child: NeuraShell(child: child ?? const SizedBox.shrink()),
        );
      },
      home: const EnhancedNavigation(),
    );
  }
}
