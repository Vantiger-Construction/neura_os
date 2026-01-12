import 'package:flutter/material.dart';

import 'core/neura_event_bus.dart';
import 'core/neura_fault_system.dart';
import 'avatar/avatar_globals.dart';
import 'avatar/avatar_orchestrator.dart';
import 'modules/core/app_log.dart';
import 'modules/core/error_handler.dart';
import 'src/app.dart';
import 'src/modules/focus/focus_controller.dart';
import 'src/shell/shell_prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Don't let logging crash startup.
  await AppLog.instance.init();
  ErrorHandler.install();

  // Wire up global error handling with Neura Fault System
  NeuraFaultSystem.install(
    bus: NeuraEventBus.I,
    controller: AvatarGlobals.controller,
  );

  // Start orchestrator (drives Neura's expressions based on events)
  final orchestrator = AvatarOrchestrator(
    controller: AvatarGlobals.controller,
    bus: NeuraEventBus.I,
  )..start();

  // OS-level state
  await ShellPrefsController.instance.init();
  await FocusController.instance.init();

  runApp(const NeuraApp());
}
