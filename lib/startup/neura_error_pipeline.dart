import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'neura_bootstrap_log.dart';
import 'neura_error_redactor.dart';
import 'neura_isolate_error_listener.dart';

typedef NeuraStructuredErrorSink =
    Future<void> Function(Map<String, Object?> payload);
typedef NeuraErrorNotice = void Function();
typedef NeuraErrorObserver = void Function(Map<String, Object?> payload);

/// A display-safe summary of a fatal error.
class NeuraFatalError {
  final String source;
  final String phase;

  const NeuraFatalError({required this.source, required this.phase});
}

/// Single owner for uncaught Flutter, platform, zone and root-isolate errors.
///
/// It is installed before any optional plugin calls. Until AppLog is ready,
/// sanitized records go to a small dependency-free local file and a bounded
/// memory queue. [attachAppLog] flushes that queue and becomes the sole sink
/// for subsequent records, so ErrorHandler never installs competing global
/// callbacks.
class NeuraErrorPipeline {
  NeuraErrorPipeline._();

  static final NeuraErrorPipeline instance = NeuraErrorPipeline._();

  static const int _maxPendingRecords = 32;
  static const Duration _duplicateWindow = Duration(seconds: 2);

  final ValueNotifier<NeuraFatalError?> fatalError =
      ValueNotifier<NeuraFatalError?>(null);

  final List<Map<String, Object?>> _pendingRecords = [];
  final Map<String, DateTime> _recentSignatures = {};
  final Set<NeuraErrorObserver> _observers = {};

  bool _installed = false;
  FlutterExceptionHandler? _previousFlutterHandler;
  bool Function(Object, StackTrace)? _previousPlatformHandler;
  NeuraIsolateErrorListener? _isolateErrorListener;
  NeuraStructuredErrorSink? _appLogSink;
  NeuraErrorNotice? _notice;
  Future<void> _sinkWrites = Future<void>.value();

  String get bootstrapLogLocation => NeuraBootstrapLog.displayLocation;

  /// Installs global handlers exactly once for this isolate.
  void installGlobalHandlers() {
    if (_installed) return;
    _installed = true;

    _previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = _onFlutterError;

    _previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = _onPlatformError;

    ErrorWidget.builder = _buildErrorWidget;

    // PlatformDispatcher covers root-isolate async errors on Flutter-managed
    // event loops. The isolate listener adds coverage for errors delivered
    // directly by the root isolate. Dedupe suppresses double delivery.
    try {
      _isolateErrorListener = NeuraIsolateErrorListener.attach(_onIsolateError);
    } catch (error, stackTrace) {
      _isolateErrorListener?.close();
      _isolateErrorListener = null;
      captureBootstrapWarning(
        error,
        stackTrace,
        source: 'isolate_error_listener',
      );
    }
  }

  /// Adds the UI notification used by the normal app shell. This does not
  /// install or replace any global handler.
  void attachNotice(NeuraErrorNotice notice) {
    _notice = notice;
  }

  /// Registers an additional in-process consumer without changing the global
  /// error callbacks. The observer receives only the sanitized stable payload.
  /// Returns a function that removes this observer.
  VoidCallback addObserver(NeuraErrorObserver observer) {
    _observers.add(observer);
    return () => _observers.remove(observer);
  }

  /// Hands pending bootstrap records to AppLog, then makes it the sole sink
  /// for new error records. Safe to call repeatedly.
  Future<void> attachAppLog(NeuraStructuredErrorSink sink) async {
    _appLogSink = sink;
    if (_pendingRecords.isNotEmpty) {
      final pending = List<Map<String, Object?>>.of(_pendingRecords);
      _pendingRecords.clear();
      for (final record in pending) {
        _enqueueAppLog(record);
      }
    }
    await _sinkWrites;
  }

  Future<void> drain() async {
    await _sinkWrites;
    await NeuraBootstrapLog.drain();
  }

  /// Captures an expected-but-important bootstrap degradation without
  /// replacing the running UI.
  void captureBootstrapWarning(
    Object error,
    StackTrace stackTrace, {
    required String source,
  }) {
    capture(
      error,
      stackTrace,
      source: source,
      fatal: false,
      phase: 'bootstrap',
    );
  }

  /// Captures an error in the stable structure consumed by AppLog and future
  /// diagnostics export.
  void capture(
    Object error,
    StackTrace stackTrace, {
    required String source,
    required bool fatal,
    required String phase,
    String? errorType,
    bool suppressNotice = false,
  }) {
    try {
      final sanitizedErrorType = NeuraErrorRedactor.tag(
        errorType ?? error.runtimeType.toString(),
        fallback: 'UnknownError',
      );
      final payload = <String, Object?>{
        'source': NeuraErrorRedactor.tag(source),
        'error_type': sanitizedErrorType,
        // Never persist error.toString(): provider/plugin exceptions can echo
        // prompts, credentials, filenames, or other arbitrary user content.
        'message': 'An unexpected $sanitizedErrorType was contained.',
        'stack': NeuraErrorRedactor.stack(_safeStackToString(stackTrace)),
        'fatal': fatal,
        'phase': NeuraErrorRedactor.tag(phase),
      };

      if (_isDuplicate(payload)) return;

      final immutablePayload = Map<String, Object?>.unmodifiable(payload);
      final sink = _appLogSink;
      if (sink == null) {
        if (_pendingRecords.length == _maxPendingRecords) {
          _pendingRecords.removeAt(0);
        }
        _pendingRecords.add(immutablePayload);
        unawaited(NeuraBootstrapLog.append(payload));
      } else {
        _enqueueAppLog(payload);
      }

      for (final observer in List<NeuraErrorObserver>.of(_observers)) {
        try {
          observer(immutablePayload);
        } catch (_) {}
      }

      if (fatal) {
        final summary = NeuraFatalError(source: source, phase: phase);
        // ErrorWidget.builder runs during a framework build. Deferring its
        // notifier update avoids marking the root boundary dirty mid-build.
        if (source.startsWith('flutter_')) {
          scheduleMicrotask(() => fatalError.value = summary);
        } else {
          fatalError.value = summary;
        }
      }

      if (phase == 'runtime' && !suppressNotice) _notice?.call();
    } catch (_) {
      // The error reporter is the last line of defense and must never throw.
    }
  }

  void clearFatalError() {
    fatalError.value = null;
  }

  void _onFlutterError(FlutterErrorDetails details) {
    capture(
      details.exception,
      details.stack ?? StackTrace.current,
      source: 'flutter_framework',
      fatal: false,
      phase: 'runtime',
      suppressNotice: _isBenignInkResponseRace(details),
    );

    final previous = _previousFlutterHandler;
    try {
      if (previous != null && !identical(previous, _onFlutterError)) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    } catch (_) {
      // Console presentation cannot be allowed to escape the error handler.
    }
  }

  /// Flutter's [MouseTracker]/[InkWell] hover-tracking has a longstanding
  /// framework race (flutter/flutter#89736 and duplicates): a hover or
  /// tap-down event can reach an `_InkResponseState` whose element was
  /// deactivated moments earlier, so `Material.of(context)` null-checks and
  /// throws. It's still captured and logged for diagnostics -- only the
  /// user-facing notice is skipped so the app doesn't interrupt the user
  /// over an invisible framework hiccup.
  bool _isBenignInkResponseRace(FlutterErrorDetails details) {
    if (details.exceptionAsString() !=
        'Null check operator used on a null value') {
      return false;
    }
    final stack = (details.stack ?? StackTrace.current).toString();
    return stack.contains('Material.of') && stack.contains('ink_well.dart');
  }

  bool _onPlatformError(Object error, StackTrace stackTrace) {
    capture(
      error,
      stackTrace,
      source: 'platform_dispatcher',
      fatal: true,
      phase: 'runtime',
    );

    try {
      _previousPlatformHandler?.call(error, stackTrace);
    } catch (_) {}
    // Explicitly handled: otherwise Flutter may terminate the root isolate.
    return true;
  }

  void _onIsolateError(dynamic message) {
    Object error = 'Unknown isolate error';
    StackTrace stackTrace = StackTrace.current;
    if (message is List && message.isNotEmpty) {
      error = message.first ?? error;
      if (message.length > 1 && message[1] != null) {
        stackTrace = StackTrace.fromString(message[1].toString());
      }
    } else if (message != null) {
      error = message;
    }
    capture(
      error,
      stackTrace,
      source: 'root_isolate',
      fatal: true,
      phase: 'runtime',
      errorType: 'IsolateError',
    );
  }

  Widget _buildErrorWidget(FlutterErrorDetails details) {
    capture(
      details.exception,
      details.stack ?? StackTrace.current,
      source: 'flutter_error_widget',
      fatal: false,
      phase: 'runtime',
    );
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFF0D0D1A),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Neura contained a screen error.\n'
              'Other parts of the app may still be available.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }

  bool _isDuplicate(Map<String, Object?> payload) {
    final now = DateTime.now();
    _recentSignatures.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _duplicateWindow,
    );
    final stack = payload['stack']! as String;
    final firstFrame = stack.split('\n').first;
    final signature = '${payload['fatal']}|${payload['message']}|$firstFrame';
    if (_recentSignatures.containsKey(signature)) return true;
    _recentSignatures[signature] = now;
    return false;
  }

  String _safeStackToString(StackTrace stackTrace) {
    try {
      return stackTrace.toString();
    } catch (_) {
      return 'Stack unavailable';
    }
  }

  void _enqueueAppLog(Map<String, Object?> payload) {
    final sink = _appLogSink;
    if (sink == null) return;
    _sinkWrites = _sinkWrites
        .then((_) async {
          try {
            await sink(payload);
          } catch (_) {
            // AppLog can become unavailable after a successful handoff (disk
            // full, revoked storage, data-wipe suspension). Preserve the already
            // sanitized record in the independent bounded bootstrap log. A later
            // record still retries AppLog through the same sink.
            await NeuraBootstrapLog.append(payload);
          }
        })
        .catchError((_) {});
  }

  @visibleForTesting
  void resetForTesting() {
    fatalError.value = null;
    _pendingRecords.clear();
    _recentSignatures.clear();
    _appLogSink = null;
    _notice = null;
    _observers.clear();
    _sinkWrites = Future<void>.value();
  }
}

/// Root-level fallback that remains renderable when bootstrap or an uncaught
/// asynchronous error leaves Neura in an unsafe state.
class NeuraErrorBoundary extends StatelessWidget {
  final Widget child;
  final VoidCallback onContinueInSafeMode;

  const NeuraErrorBoundary({
    super.key,
    required this.child,
    required this.onContinueInSafeMode,
  });

  @override
  Widget build(BuildContext context) {
    final pipeline = NeuraErrorPipeline.instance;
    return ValueListenableBuilder<NeuraFatalError?>(
      valueListenable: pipeline.fatalError,
      child: child,
      builder: (context, failure, app) {
        if (failure == null) return app!;
        return _NeuraRecoveryApp(
          logLocation: pipeline.bootstrapLogLocation,
          onRetry: pipeline.clearFatalError,
          onContinueInSafeMode: () {
            onContinueInSafeMode();
            pipeline.clearFatalError();
          },
        );
      },
    );
  }
}

class _NeuraRecoveryApp extends StatelessWidget {
  final String logLocation;
  final VoidCallback onRetry;
  final VoidCallback onContinueInSafeMode;

  const _NeuraRecoveryApp({
    required this.logLocation,
    required this.onRetry,
    required this.onContinueInSafeMode,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: const Color(0xFF0D0D1A),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.health_and_safety_outlined,
                      size: 54,
                      color: Colors.orangeAccent,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Neura entered recovery mode',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'An unexpected startup or screen error was contained. '
                      'Your private content was not included in this message.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: onContinueInSafeMode,
                      icon: const Icon(Icons.shield_outlined),
                      label: const Text('Continue in Safe Mode'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Bootstrap diagnostic log',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    SelectionArea(
                      child: Text(
                        logLocation,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
