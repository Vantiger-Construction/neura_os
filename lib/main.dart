import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager_plus/window_manager_plus.dart';

import 'mascot/mascot_window_app.dart';
import 'mascot/mascot_window_service.dart';
import 'mascot/neura_window_role.dart';
import 'reliability/safe_boot.dart';
import 'src/app.dart';
import 'startup/neura_error_pipeline.dart';
import 'startup/neura_process_exit.dart';

const String kLaunchSmokeTestArgument = '--launch-smoke-test';
const int kLaunchSmokeTestSuccessExitCode = 73;
bool _rootAttached = false;
bool _fatalListenerInstalled = false;
bool _bootstrapFinished = false;
bool _launchSmokeTestActive = false;
bool _launchSmokeTestExitStarted = false;
final ValueNotifier<Widget?> _launchTarget = ValueNotifier<Widget?>(null);

@visibleForTesting
bool supportsWindowManagerPlus({
  required TargetPlatform platform,
  required bool isWeb,
}) {
  if (isWeb) return false;
  return platform == TargetPlatform.windows ||
      platform == TargetPlatform.macOS;
}

@visibleForTesting
bool launchSmokeTestRequested(
  List<String> arguments, {
  required bool isWeb,
}) {
  return !isWeb && arguments.contains(kLaunchSmokeTestArgument);
}

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
void main(List<String> args) {
  runZonedGuarded<void>(
    () {
      // Binding creation and runApp must happen in the same zone. Flutter
      // treats a split here as a zone mismatch and can fail before first frame.
      WidgetsFlutterBinding.ensureInitialized();

      final errors = NeuraErrorPipeline.instance;
      errors.installGlobalHandlers();
      if (!_fatalListenerInstalled) {
        _fatalListenerInstalled = true;
        errors.fatalError.addListener(_onFatalError);
      }

      // Attach a dependency-free frame before any MethodChannel/plugin call.
      // Role discovery can now fail or time out without leaving a blank window.
      _attachBootstrapRoot();
      if (launchSmokeTestRequested(args, isWeb: kIsWeb)) {
        _launchSmokeTestActive = true;
        _launchTarget.value = const _NeuraLaunchSmokeTestFrame();
        errors.addObserver((_) {
          _scheduleCapturedSmokeFailureExit();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_runLaunchSmokeTest());
        });
        return;
      }
      unawaited(
        _bootstrapWindowAndLaunch().then((_) {
          _bootstrapFinished = true;
        }),
      );
    },
    (error, stackTrace) {
      final phase = _bootstrapFinished ? 'runtime' : 'bootstrap';
      NeuraErrorPipeline.instance.capture(
        error,
        stackTrace,
        source: 'root_zone',
        fatal: true,
        phase: phase,
      );
      _bootstrapFinished = true;
      if (_rootAttached && !_launchSmokeTestActive) {
        _selectPrimaryAfterEarlyFatalError();
      }
    },
  );
}

Future<void> _bootstrapWindowAndLaunch() async {
  final platform = defaultTargetPlatform;
  if (!supportsWindowManagerPlus(platform: platform, isWeb: kIsWeb)) {
    _attachRoot(const NeuroCompanionApp());
    return;
  }

  if (platform == TargetPlatform.windows) {
    late final ({int windowId, bool isMascot}) role;
    try {
      // The custom channel is registered immediately after the engine starts,
      // so tolerate that narrow MissingPlugin race without waiting forever for
      // UI. Failure degrades only the optional companion-window feature.
      role = await retryBootstrapOperation(
        NeuraWindowRole.get,
        attempts: 3,
        timeout: const Duration(milliseconds: 650),
        retryDelay: const Duration(milliseconds: 90),
      );
    } catch (error, stackTrace) {
      MascotWindowService.I.disableForProcess();
      NeuraErrorPipeline.instance.captureBootstrapWarning(
        error,
        stackTrace,
        source: 'window_role',
      );
      _attachRoot(const NeuroCompanionApp());
      return;
    }

    if (role.isMascot) {
      try {
        await WindowManagerPlus.ensureInitialized(role.windowId).timeout(
          const Duration(seconds: 3),
        );
        _attachRoot(const MascotWindowApp());
      } catch (error, stackTrace) {
        NeuraErrorPipeline.instance.capture(
          error,
          stackTrace,
          source: 'mascot_window_manager',
          fatal: true,
          phase: 'bootstrap',
        );
        // Attach a minimal root even on plugin failure so the secondary engine
        // shows recovery UI rather than terminating without a frame.
        _attachRoot(const MascotWindowApp());
      }
      return;
    }

    // The primary app must not wait on this optional plugin. Its first Flutter
    // frame is attached now; companion-window capability initializes in the
    // background and is permanently disabled for this process if unavailable.
    _attachRoot(const NeuroCompanionApp());
    final windowManagerReady = _initializePrimaryWindowManager(role.windowId);
    MascotWindowService.I.deferCreationUntil(windowManagerReady);
    unawaited(windowManagerReady);
    return;
  }

  // macOS has no Neura role channel or secondary mascot integration. The
  // primary app renders first and window_manager_plus remains best effort.
  _attachRoot(const NeuroCompanionApp());
  final windowManagerReady = _initializePrimaryWindowManager(0);
  MascotWindowService.I.deferCreationUntil(windowManagerReady);
  unawaited(windowManagerReady);
}

Future<void> _initializePrimaryWindowManager(int windowId) async {
  try {
    await WindowManagerPlus.ensureInitialized(windowId).timeout(
      const Duration(seconds: 3),
    );
  } catch (error, stackTrace) {
    MascotWindowService.I.disableForProcess();
    NeuraErrorPipeline.instance.captureBootstrapWarning(
      error,
      stackTrace,
      source: 'primary_window_manager',
    );
  }
}

void _attachRoot(Widget app) {
  _attachBootstrapRoot();
  _launchTarget.value = app;
}

void _attachBootstrapRoot() {
  if (_rootAttached) return;
  _rootAttached = true;
  runApp(
    NeuraErrorBoundary(
      onContinueInSafeMode: () {
        SafeBoot.instance.preselectSafeModeForProcess();
      },
      child: _NeuraLaunchHost(target: _launchTarget),
    ),
  );
}

void _onFatalError() {
  if (_launchSmokeTestActive) {
    _scheduleCapturedSmokeFailureExit();
    return;
  }
  _selectPrimaryAfterEarlyFatalError();
}

void _selectPrimaryAfterEarlyFatalError() {
  if (_launchTarget.value != null ||
      NeuraErrorPipeline.instance.fatalError.value == null) {
    return;
  }
  MascotWindowService.I.disableForProcess();
  _attachRoot(const NeuroCompanionApp());
}

class _NeuraLaunchHost extends StatelessWidget {
  final ValueListenable<Widget?> target;

  const _NeuraLaunchHost({required this.target});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Widget?>(
      valueListenable: target,
      builder: (context, app, _) => app ?? const _NeuraBootstrapFrame(),
    );
  }
}

class _NeuraBootstrapFrame extends StatelessWidget {
  const _NeuraBootstrapFrame();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF0D0D1A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 18),
              Text(
                'Starting Neura safely…',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeuraLaunchSmokeTestFrame extends StatelessWidget {
  const _NeuraLaunchSmokeTestFrame();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF0D0D1A),
        body: Center(
          child: Text(
            'Verifying Neura launch…',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

Future<void> _runLaunchSmokeTest() async {
  try {
    await _verifyLaunchSmokeTest().timeout(const Duration(seconds: 6));
    // A normal Windows message-loop exit returns 0. Use a dedicated sentinel
    // so an immediate window close cannot masquerade as smoke-test success.
    await _exitLaunchSmokeTest(kLaunchSmokeTestSuccessExitCode);
  } on TimeoutException catch (error, stackTrace) {
    await _failLaunchSmokeTest(error, stackTrace, exitCode: 3);
  } catch (error, stackTrace) {
    await _failLaunchSmokeTest(error, stackTrace, exitCode: 2);
  }
}

Future<void> _verifyLaunchSmokeTest() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
    throw UnsupportedError(
      'Launch smoke verification is currently supported on Windows only.',
    );
  }

  final role = await retryBootstrapOperation(
    NeuraWindowRole.get,
    attempts: 3,
    timeout: const Duration(milliseconds: 650),
    retryDelay: const Duration(milliseconds: 90),
  );
  if (role.isMascot || role.windowId != 0) {
    throw StateError('Launch smoke test did not start in the primary window.');
  }
  await WindowManagerPlus.ensureInitialized(role.windowId).timeout(
    const Duration(seconds: 3),
  );
}

Future<void> _failLaunchSmokeTest(
  Object error,
  StackTrace stackTrace, {
  required int exitCode,
}) async {
  if (_launchSmokeTestExitStarted) return;
  _launchSmokeTestExitStarted = true;
  NeuraErrorPipeline.instance.capture(
    error,
    stackTrace,
    source: 'launch_smoke_test',
    fatal: false,
    phase: 'bootstrap',
  );
  await _drainSmokeTestLogs();
  exitNeuraProcess(exitCode);
}

void _scheduleCapturedSmokeFailureExit() {
  if (!_launchSmokeTestActive || _launchSmokeTestExitStarted) return;
  _launchSmokeTestExitStarted = true;
  scheduleMicrotask(() => unawaited(_exitAfterCapturedSmokeFailure()));
}

Future<void> _exitAfterCapturedSmokeFailure() async {
  await _drainSmokeTestLogs();
  exitNeuraProcess(2);
}

Future<void> _exitLaunchSmokeTest(int exitCode) async {
  if (_launchSmokeTestExitStarted) return;
  _launchSmokeTestExitStarted = true;
  await _drainSmokeTestLogs();
  exitNeuraProcess(exitCode);
}

Future<void> _drainSmokeTestLogs() async {
  try {
    await NeuraErrorPipeline.instance.drain().timeout(
      const Duration(seconds: 2),
    );
  } catch (_) {
    // Exit deterministically even if the diagnostic destination is blocked.
  }
}

/// Bounded retry for native bootstrap channels that can race plugin
/// registration. Kept public for a plugin-free unit test.
@visibleForTesting
Future<T> retryBootstrapOperation<T>(
  Future<T> Function() operation, {
  int attempts = 3,
  Duration timeout = const Duration(milliseconds: 650),
  Duration retryDelay = const Duration(milliseconds: 90),
}) async {
  if (attempts < 1) {
    throw ArgumentError.value(attempts, 'attempts', 'must be at least 1');
  }
  Object? lastError;
  StackTrace? lastStackTrace;

  for (var attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await operation().timeout(timeout);
    } catch (error, stackTrace) {
      lastError = error;
      lastStackTrace = stackTrace;
      if (attempt < attempts) await Future<void>.delayed(retryDelay);
    }
  }

  Error.throwWithStackTrace(lastError!, lastStackTrace!);
}
