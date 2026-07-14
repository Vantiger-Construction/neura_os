import 'package:flutter/material.dart';
import 'package:window_manager_plus/window_manager_plus.dart';

import 'mascot/mascot_window_app.dart';
import 'mascot/neura_window_role.dart';
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
/// same entrypoint for every window it creates, running a fresh engine in
/// the same process. Which window this is (main app vs. the floating
/// mascot) and its real window id come from [NeuraWindowRole], not from
/// `args` -- see that class for why.
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final role = await NeuraWindowRole.get();
  await WindowManagerPlus.ensureInitialized(role.windowId);

  if (role.isMascot) {
    runApp(const MascotWindowApp());
    return;
  }

  runApp(const NeuroCompanionApp());
}
