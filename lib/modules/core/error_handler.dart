import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_log.dart';

/// Global error handling that:
/// - logs errors
/// - shows a friendly (and slightly comedic) snackbar
class ErrorHandler {
  static final _snackKey = GlobalKey<ScaffoldMessengerState>();
  static GlobalKey<ScaffoldMessengerState> get scaffoldMessengerKey =>
      _snackKey;

  static void install() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _logFlutterError(details);
      if (!_isBenignInkResponseRace(details)) {
        _toast('Neura caught a glitch and filed it under "Cosmic Weirdness."');
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(AppLog.instance.error('zone_error', {
        'error': error.toString(),
        'stack': stack.toString(),
      }));
      _toast('Parallel universe patch incoming… (kidding, but I logged it).');
      return true;
    };
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
          SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  static Future<void> _logFlutterError(FlutterErrorDetails details) async {
    await AppLog.instance.error('flutter_error', {
      'exception': details.exceptionAsString(),
      'library': details.library ?? '',
      'context': details.context?.toDescription() ?? '',
      'stack': (details.stack ?? StackTrace.current).toString(),
    });
  }
}
