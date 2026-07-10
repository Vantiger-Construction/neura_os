import 'package:flutter/material.dart';
import 'package:window_manager_plus/window_manager_plus.dart';

import 'mascot/mascot_window_app.dart';
import 'mascot/mascot_window_service.dart';
import 'src/app.dart';

/// Entry point.
///
/// Calls [runApp] as fast as possible (after binding init only) so the window
/// is visible within a single frame.  All heavy initialization — Supabase,
/// SharedPreferences, mic, avatar, memory runtime — is handled inside
/// [NeuraStartupCoordinator], which is fired from [NeuraBootScreen] and runs
/// concurrently with the first UI frame.
///
/// window_manager_plus (used for the floating avatar window) re-enters this
/// same entrypoint for every window it creates, passing the window's id as
/// `args[0]` and any custom payload (see [MascotWindowService]) after that.
/// The main window is launched natively with no such args, so it defaults to
/// id 0 and an empty payload.
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final windowId = args.isEmpty ? 0 : int.tryParse(args[0]) ?? 0;
  await WindowManagerPlus.ensureInitialized(windowId);

  if (args.length > 1 && args[1] == kMascotWindowArgument) {
    runApp(const MascotWindowApp());
    return;
  }

  runApp(const NeuroCompanionApp());
}
