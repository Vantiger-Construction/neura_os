import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'avatar/avatar_globals.dart';
import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  // Avatar prefs are helpful but should never block startup.
  try {
    await AvatarGlobals.service.init();
  } catch (_) {
    // Non-fatal: app can still boot without avatar assets.
  }

  await SentryFlutter.init(
    (options) {
      options.dsn = 'YOUR_SENTRY_DSN';
    },
    appRunner: () => runApp(const NeuraApp()),
  );
}
