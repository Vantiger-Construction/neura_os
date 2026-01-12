import 'package:flutter/material.dart';

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

  // OS-level state
  await ShellPrefsController.instance.init();
  await FocusController.instance.init();

  runApp(const NeuraApp());
}
