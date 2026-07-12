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
      _toast('Neura caught a glitch and filed it under "Cosmic Weirdness."');
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
