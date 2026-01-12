import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'neura_events.dart';

typedef NeuraErrorSink = void Function(NeuraErrorEvent event);

class NeuraDiagnostics {
  /// Wires global error hooks so unexpected exceptions become **events** instead of silent deaths.
  ///
  /// - In debug, Flutter still prints loudly (good).
  /// - In release, we keep the app alive when possible and surface the error as a NeuraErrorEvent.
  static void wireGlobalErrorHooks({required NeuraErrorSink onErrorEvent}) {
    // Flutter framework errors (build/layout/async in widget tree)
    final FlutterExceptionHandler? prior = FlutterError.onError;

    FlutterError.onError = (FlutterErrorDetails details) {
      try {
        onErrorEvent(NeuraErrorEvent(
          details.exception,
          stack: details.stack,
          hint: details.context?.toDescription(),
        ));
      } catch (_) {}

      // Keep default behavior:
      // - Debug: dump to console
      // - Release/Profile: forward to prior handler (if any)
      if (kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      } else {
        if (prior != null) prior(details);
      }
    };

    // Platform / zone errors (outside Flutter framework)
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      try {
        onErrorEvent(NeuraErrorEvent(error, stack: stack, hint: 'PlatformDispatcher.onError'));
      } catch (_) {}
      // Return true = handled (prevents hard crash)
      return true;
    };

    // Optional: wrap your runApp call in runZonedGuarded if you want extra coverage.
  }

  /// Optional: cute-but-honest crash screen fallback for totally unrecoverable errors.
  static Widget fallbackErrorWidget(Object error) {
    return Material(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Neura hit a turbulence pocket.\n\n$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
