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
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _logFlutterError(details);
      if (!_isBenignInkResponseRace(details)) {
        _toast('Neura caught a glitch and filed it under "Cosmic Weirdness."');
      }
    };

  /// Called once the regular AppLog has initialized. Pending early records are
  /// copied into it, and it becomes the only sink for future captured errors.
  static Future<void> flushBootstrapToAppLog() {
    return NeuraErrorPipeline.instance.attachAppLog(
      (payload) => AppLog.instance.errorChecked('uncaught_error', payload),
    );
  }

  /// Flutter's [MouseTracker]/[InkWell] hover-tracking has a longstanding
  /// framework race (flutter/flutter#89736 and duplicates): a hover or
  /// tap-down event can reach an `_InkResponseState` whose element was
  /// deactivated moments earlier, so `Material.of(context)` null-checks and
  /// throws. It's caught here, never corrupts state or crashes the app, and
  /// still gets logged -- only the user-facing "glitch" toast is skipped so
  /// the app doesn't interrupt the user over an invisible framework hiccup.
  static bool _isBenignInkResponseRace(FlutterErrorDetails details) {
    if (details.exceptionAsString() != 'Null check operator used on a null value') {
      return false;
    }
    final stack = (details.stack ?? StackTrace.current).toString();
    return stack.contains('Material.of') && stack.contains('ink_well.dart');
  }

  static void _toast(String msg) {
    final messenger = _snackKey.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 3),
        ),
      );
  }
}
