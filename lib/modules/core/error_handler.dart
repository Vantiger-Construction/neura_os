import 'package:flutter/material.dart';

import '../../startup/neura_error_pipeline.dart';
import 'app_log.dart';

/// Global error handling that:
/// - logs errors
/// - shows a friendly (and slightly comedic) snackbar
class ErrorHandler {
  static final _snackKey = GlobalKey<ScaffoldMessengerState>();
  static GlobalKey<ScaffoldMessengerState> get scaffoldMessengerKey =>
      _snackKey;

  /// Connects Neura's normal UI notification to the bootstrap-installed error
  /// pipeline. This method deliberately does not replace FlutterError or
  /// PlatformDispatcher callbacks; [NeuraErrorPipeline] remains their single
  /// owner for the full process lifetime.
  static void install() {
    final pipeline = NeuraErrorPipeline.instance;
    pipeline.installGlobalHandlers();
    pipeline.attachNotice(
      () => _toast('Neura contained an error and saved a private diagnostic.'),
    );
  }

  /// Called once the regular AppLog has initialized. Pending early records are
  /// copied into it, and it becomes the only sink for future captured errors.
  static Future<void> flushBootstrapToAppLog() {
    return NeuraErrorPipeline.instance.attachAppLog(
      (payload) => AppLog.instance.errorChecked('uncaught_error', payload),
    );
  }

  static void _toast(String msg) {
    final messenger = _snackKey.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
  }
}
