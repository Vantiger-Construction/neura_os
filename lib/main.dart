import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'modules/core/app_log.dart';
import 'modules/core/error_handler.dart';
import 'src/app.dart';
import 'src/modules/focus/focus_controller.dart';
import 'src/shell/shell_prefs.dart';
import 'services/neura_voice_pack.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  // Don't let logging crash startup.
  await AppLog.instance.init();
  ErrorHandler.install();

  // OS-level state
  await ShellPrefsController.instance.init();
  await FocusController.instance.init();

  // Voice/talk/viseme stream for the Rive resident (non-blocking safety)
  try {
    await NeuraVoicePack.I.init(enableMic: true);
  } catch (_) {
    // If mic permissions / audio init fail, the OS should still boot.
  }

  runApp(const NeuroCompanionApp());
}
