import 'package:flutter/material.dart';

import 'src/app.dart';

/// Entry point.
///
/// Calls [runApp] as fast as possible (after binding init only) so the window
/// is visible within a single frame.  All heavy initialization — Supabase,
/// SharedPreferences, mic, avatar, memory runtime — is handled inside
/// [NeuraStartupCoordinator], which is fired from [NeuraBootScreen] and runs
/// concurrently with the first UI frame.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NeuroCompanionApp());
}
