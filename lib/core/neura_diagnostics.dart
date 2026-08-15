import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../startup/neura_error_pipeline.dart';
import 'neura_events.dart';

typedef NeuraErrorSink = void Function(NeuraErrorEvent event);

class NeuraDiagnostics {
  static VoidCallback? _removeObserver;

  /// Wires global error hooks so unexpected exceptions become **events** instead of silent deaths.
  ///
  /// - In debug, Flutter still prints loudly (good).
  /// - In release, we keep the app alive when possible and surface the error as a NeuraErrorEvent.
  static void wireGlobalErrorHooks({required NeuraErrorSink onErrorEvent}) {
    final pipeline = NeuraErrorPipeline.instance;
    pipeline.installGlobalHandlers();
    _removeObserver?.call();
    _removeObserver = pipeline.addObserver((payload) {
      try {
        final stackText = payload['stack']?.toString() ?? '';
        onErrorEvent(
          NeuraErrorEvent(
            payload['message']?.toString() ?? 'Unknown error',
            stack: stackText.isEmpty ? null : StackTrace.fromString(stackText),
            hint: '${payload['source'] ?? 'unknown'} '
                '(${payload['phase'] ?? 'runtime'})',
          ),
        );
      } catch (_) {}
    });
  }

  /// Optional: cute-but-honest crash screen fallback for totally unrecoverable errors.
  static Widget fallbackErrorWidget(Object error) {
    final errorType = error.runtimeType.toString();
    return Material(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Neura hit a turbulence pocket.\n\n'
            '$errorType details withheld.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
