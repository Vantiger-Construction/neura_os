import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../avatar/avatar_globals.dart';
import '../avatar/avatar_orchestrator.dart';
import '../avatar/avatar_orchestrator_viseme_ext.dart';
import '../config/supabase_config.dart';
import '../core/neura_event_bus.dart';
import '../intelligence/neura_intelligence_controller.dart';
import '../modules/core/app_log.dart';
import '../modules/core/error_handler.dart';
import '../modules/human/human_prefs_controller.dart';
import '../modules/humor/joke_prefs_controller.dart';
import '../neura_runtime/neura_runtime_controller.dart';
import '../notifications/neura_notifications_prefs.dart';
import '../notifications/neura_notifications_service.dart';
import '../reliability/module_health_monitor.dart';
import '../reliability/safe_boot.dart';
import '../reliability/timeline_vault.dart';
import '../services/ambient_listening_prefs.dart';
import '../services/ambient_listening_service.dart';
import '../services/app_lock_prefs.dart';
import '../services/neura_ai_service.dart';
import '../services/neura_provider_credentials.dart';
import '../services/neura_swarm_service.dart';
import '../services/wake_word_listener_service.dart';
import '../services/wake_word_prefs.dart';
import '../src/modules/focus/focus_controller.dart';
import '../src/shell/shell_prefs.dart';
import 'neura_error_pipeline.dart';
import 'neura_prefs_cache.dart';

@visibleForTesting
bool supportsNativeNeuraSwarm({
  required TargetPlatform platform,
  required bool isWeb,
}) =>
    !isWeb && platform == TargetPlatform.windows;

/// Native audio is deliberately absent from the automatic launch path.
///
/// Both services initialize themselves on the first user-requested playback.
/// Keeping their Windows plugins lazy prevents an optional AudioPlayer/TTS
/// engine failure from taking down the process before Neura is usable.
@visibleForTesting
const bool kNativeAudioStartupIsLazy = true;

@visibleForTesting
bool shouldInitializeNativeNeuraSwarm({
  required TargetPlatform platform,
  required bool isWeb,
  required bool safeMode,
  required bool hasProviderCredential,
}) =>
    !safeMode &&
    hasProviderCredential &&
    supportsNativeNeuraSwarm(platform: platform, isWeb: isWeb);

@visibleForTesting
bool shouldInspectSupabaseSession({
  required bool safeMode,
  required bool configured,
  required bool initialized,
}) =>
    !safeMode && configured && initialized;

/// One stage in the startup sequence (label + 0.0–1.0 progress).
class NeuraBootStage {
  final String label;
  final double progress;
  const NeuraBootStage(this.label, this.progress);
}

class NeuraBootFailure {
  final String module;
  final String message;

  const NeuraBootFailure({required this.module, required this.message});
}

/// Owns the complete Neura boot sequence.
///
/// Call [boot] from NeuraBootScreen and again after a displayed critical
/// failure when the user requests a retry.
/// Listen to [stage] for progress and [ready] for the done signal.
class NeuraStartupCoordinator {
  NeuraStartupCoordinator._();
  static final NeuraStartupCoordinator instance = NeuraStartupCoordinator._();

  // Avatar runtime objects held for app lifetime.
  // ignore: unused_field
  AvatarOrchestrator? _orchestrator;
  // ignore: unused_field
  AvatarVisemeWiring? _visemeWiring;
  StreamSubscription<Object>? _timelineSubscription;

  Future<void>? _bootInFlight;
  bool _safeModeRuntimeGuardInstalled = false;
  bool _notificationsStarted = false;
  bool _swarmStarted = false;
  bool _runtimeStarted = false;
  bool _supabaseInitialized = false;

  bool get supabaseInitialized => _supabaseInitialized;

  /// Current boot stage (label + fraction progress).
  final ValueNotifier<NeuraBootStage> stage =
      ValueNotifier(const NeuraBootStage('Initializing…', 0.0));

  /// Flips to true once boot completes (even if some non-fatal steps failed).
  final ValueNotifier<bool> ready = ValueNotifier(false);

  /// A critical startup failure that requires an explicit retry.
  final ValueNotifier<NeuraBootFailure?> failure = ValueNotifier(null);

  /// True while the initial boot or a user-requested retry is running.
  final ValueNotifier<bool> booting = ValueNotifier(false);

  /// Runs the startup sequence. Concurrent calls share one attempt; after a
  /// critical failure a later call starts a fresh retry.
  Future<void> boot() {
    if (ready.value) return Future<void>.value();
    final existing = _bootInFlight;
    if (existing != null) return existing;

    failure.value = null;
    booting.value = true;
    _supabaseInitialized = false;
    _emit('Starting Neura…', 0.0);

    late final Future<void> operation;
    operation = _runBootGuarded().whenComplete(() {
      booting.value = false;
      if (identical(_bootInFlight, operation)) _bootInFlight = null;
    });
    _bootInFlight = operation;
    return operation;
  }

  Future<void> _runBootGuarded() async {
    try {
      await _runBoot();
    } catch (error, stackTrace) {
      NeuraErrorPipeline.instance.capture(
        error,
        stackTrace,
        source: 'startup_coordinator',
        fatal: true,
        phase: 'startup',
      );
      ModuleHealthMonitor.instance.failed('StartupCoordinator', error);
      debugPrint(
        '[NeuraStartup] critical startup failure: ${error.runtimeType}',
      );
      failure.value = const NeuraBootFailure(
        module: 'StartupCoordinator',
        message: 'Neura could not finish starting. Review the error and retry.',
      );
      _emit('Startup paused', stage.value.progress);
    }
  }

  Future<void> _runBoot() async {
    // Safe Boot marker is written before native services start. If two
    // consecutive launches fail to reach completeBoot(), optional native and
    // network services are skipped on the next launch.
    try {
      await SafeBoot.instance.beginBoot();
      ModuleHealthMonitor.instance.healthy('SafeBoot');
    } catch (error, stackTrace) {
      // If the boot marker cannot be read or written, Neura cannot know
      // whether the previous native startup completed. Fail closed for this
      // session instead of loading the very services Safe Boot protects.
      SafeBoot.instance.safeMode.value = true;
      NeuraErrorPipeline.instance.capture(
        error,
        stackTrace,
        source: 'startup_SafeBoot',
        fatal: false,
        phase: 'startup',
      );
      ModuleHealthMonitor.instance.failed('SafeBoot', error);
    }

    // 1 – Error handler (synchronous, must be first)
    _emit('Setting up error handling…', 0.05);
    ErrorHandler.install();

    // 2 – Logging
    _emit('Starting logger…', 0.10);
    var appLogReady = await _safe(AppLog.instance.initChecked, 'AppLog');
    if (appLogReady) {
      await ErrorHandler.flushBootstrapToAppLog();
    }
    await _safe(TimelineVault.instance.initialize, 'TimelineVault');
    _timelineSubscription ??= NeuraEventBus.I.rawStream.listen((event) {
      unawaited(
        TimelineVault.instance
            .append(
              'event_bus',
              data: {'type': event.runtimeType.toString()},
            )
            .catchError((_) {}),
      );
    });
    try {
      await TimelineVault.instance.append('boot_started', data: {
        'safe_mode': SafeBoot.instance.safeMode.value,
        'previous_failures': SafeBoot.instance.consecutiveFailures,
      });
    } catch (_) {}

    // 3 – SharedPreferences (single cached instance used by all services)
    _emit('Loading preferences…', 0.20);
    final prefsReady = await _safe(
      NeuraPrefsCache.init,
      'PrefsCache',
      critical: true,
    );
    if (!prefsReady) {
      failure.value = const NeuraBootFailure(
        module: 'PrefsCache',
        message: 'Neura could not open device preferences. '
            'Check storage access, then retry startup.',
      );
      _emit('Preferences unavailable', 0.20);
      return;
    }
    if (!appLogReady) {
      appLogReady = await _safe(
        AppLog.instance.initChecked,
        'AppLogAfterPrefs',
      );
      if (appLogReady) {
        await ErrorHandler.flushBootstrapToAppLog();
      }
    }

    // 4 – OS-level shell state
    _emit('Loading shell settings…', 0.30);
    await _safe(ShellPrefsController.instance.init, 'ShellPrefs');
    await _safe(FocusController.instance.init, 'FocusController');
    await _safe(HumanPrefsController.instance.init, 'HumanPrefs');
    await _safe(
      NeuraIntelligenceController.instance.initialize,
      'IntelligenceFabric',
    );
    await _safe(AppLockPrefsController.instance.init, 'AppLockPrefs');
    await _safe(JokePrefsController.instance.init, 'JokePrefs');
    await _safe(
      AmbientListeningPrefsController.instance.init,
      'AmbientListeningPrefs',
    );
    await _safe(WakeWordPrefsController.instance.init, 'WakeWordPrefs');
    await _safe(
      NeuraNotificationsPrefsController.instance.init,
      'NotificationsPrefs',
    );
    if (SafeBoot.instance.safeMode.value) {
      ModuleHealthMonitor.instance.skipped(
        'NotificationsService',
        'Safe Mode disables optional native services.',
      );
      await _safe(
        NeuraNotificationsService.instance.cancelAllForSafeMode,
        'NotificationsSafeModeCleanup',
      );
    } else {
      _notificationsStarted = await _safe(
        NeuraNotificationsService.instance.init,
        'NotificationsService',
      );
    }

    // 5 – Avatar runtime (in-memory, essentially instant)
    _emit('Waking Neura avatar…', 0.50);
    _startAvatarRuntime();

    // 6 – Voice. Mic capture and playback are started lazily by the screen or
    // user action that needs them. In particular, do not construct AudioPlayer
    // or initialize flutter_tts during launch: either native plugin failing can
    // otherwise terminate the Windows process before a recovery UI is visible.
    _emit('Preparing voice…', 0.65);
    if (SafeBoot.instance.safeMode.value) {
      ModuleHealthMonitor.instance.skipped(
        'VoicePack',
        'Disabled by Safe Mode.',
      );
      ModuleHealthMonitor.instance.skipped(
        'TtsWarmup',
        'Disabled by Safe Mode.',
      );
    } else {
      ModuleHealthMonitor.instance.skipped(
        'VoicePack',
        'Deferred until user-requested playback to keep native audio out of launch.',
      );
      ModuleHealthMonitor.instance.skipped(
        'TtsWarmup',
        'Deferred until user-requested speech to keep native TTS out of launch.',
      );
    }

    // 6b – Provider credential + Rust swarm. Existing build-time credentials
    // are migrated once into OS-backed secure storage. New builds should not
    // contain provider secrets.
    if (SafeBoot.instance.safeMode.value) {
      ModuleHealthMonitor.instance.skipped(
        'ProviderCredentials',
        'Disabled by Safe Mode.',
      );
      ModuleHealthMonitor.instance.skipped(
        'SwarmInit',
        'Disabled by Safe Mode.',
      );
    } else {
      final credentialsReady = await _safe(
        NeuraProviderCredentials.instance.initialize,
        'ProviderCredentials',
      );
      if (!credentialsReady) {
        ModuleHealthMonitor.instance.skipped(
          'SwarmInit',
          'Provider credential storage is unavailable; native swarm remains unloaded.',
        );
      } else if (!NeuraProviderCredentials.instance.hasKey) {
        ModuleHealthMonitor.instance.skipped(
          'SwarmInit',
          'No provider credential is configured; native swarm remains unloaded.',
        );
      } else if (shouldInitializeNativeNeuraSwarm(
        platform: defaultTargetPlatform,
        isWeb: kIsWeb,
        safeMode: SafeBoot.instance.safeMode.value,
        hasProviderCredential: NeuraProviderCredentials.instance.hasKey,
      )) {
        _swarmStarted = await _safe(
          () => NeuraSwarmService.instance
              .init(NeuraProviderCredentials.instance.apiKey),
          'SwarmInit',
        );
      } else {
        ModuleHealthMonitor.instance.skipped(
          'SwarmInit',
          'The packaged native swarm is currently available on Windows only.',
        );
      }
    }

    // 7 – Room / memory runtime
    _emit('Loading memory…', 0.80);
    if (SafeBoot.instance.safeMode.value) {
      ModuleHealthMonitor.instance.skipped(
        'NeuraRuntime',
        'Disabled by Safe Mode because it can dispatch optional audio.',
      );
    } else {
      _runtimeStarted = await _safe(
        NeuraRuntimeController.I.start,
        'NeuraRuntime',
      );
    }

    // 8 – Supabase (network, last + optional; gracefully skipped if placeholder keys)
    _emit('Connecting to cloud…', 0.90);
    if (!SafeBoot.instance.safeMode.value) {
      final initialized = await _safe(_initSupabase, 'Supabase');
      _supabaseInitialized = SupabaseConfig.isConfigured && initialized;
    } else {
      ModuleHealthMonitor.instance.skipped(
        'Supabase',
        'Disabled by Safe Mode.',
      );
    }

    // Done
    _emit('Ready!', 1.0);
    try {
      await TimelineVault.instance.append('boot_completed', data: {
        'safe_mode': SafeBoot.instance.safeMode.value,
      });
    } catch (_) {}
    try {
      await SafeBoot.instance.completeBoot();
    } catch (_) {}
    _installSafeModeRuntimeGuard();
    ready.value = true;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────────────────────

  void _startAvatarRuntime() {
    _orchestrator = AvatarOrchestrator(
      controller: AvatarGlobals.controller,
      bus: NeuraEventBus.I,
    )..start();

    _visemeWiring = AvatarVisemeWiring(
      controller: AvatarGlobals.controller,
      bus: NeuraEventBus.I,
    )..start();
  }

  Future<void> _initSupabase() async {
    if (!SupabaseConfig.isConfigured) {
      debugPrint(
        '[NeuraStartup] Supabase skipped — placeholder credentials detected. '
        'Add real values in lib/config/supabase_config.dart.',
      );
      return;
    }
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
  }

  /// Runs [fn] safely; logs and swallows any exception so boot always completes.
  /// Returns whether the module actually initialized.
  Future<bool> _safe(
    Future<void> Function() fn,
    String label, {
    bool critical = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    ModuleHealthMonitor.instance.starting(label);
    try {
      await fn();
      stopwatch.stop();
      ModuleHealthMonitor.instance.healthy(label, duration: stopwatch.elapsed);
      try {
        await TimelineVault.instance.append('module_healthy', data: {
          'module': label,
          'duration_ms': stopwatch.elapsedMilliseconds,
        });
      } catch (_) {}
      return true;
    } catch (e, st) {
      stopwatch.stop();
      final severity = critical ? 'critical' : 'non-fatal';
      NeuraErrorPipeline.instance.capture(
        e,
        st,
        source: 'startup_$label',
        fatal: critical,
        phase: 'startup',
      );
      ModuleHealthMonitor.instance.failed(label, e);
      debugPrint(
        '[NeuraStartup] $label failed ($severity): ${e.runtimeType}',
      );
      try {
        await TimelineVault.instance.append('module_failed', data: {
          'module': label,
          'error_type': e.runtimeType.toString(),
        });
      } catch (_) {}
      try {
        await AppLog.instance.exception(
          'startup_module_failed',
          e,
          st,
          context: <String, Object?>{
            'module': label,
            'severity': severity,
          },
        );
      } catch (_) {}
      return false;
    }
  }

  void _installSafeModeRuntimeGuard() {
    if (_safeModeRuntimeGuardInstalled) return;
    _safeModeRuntimeGuardInstalled = true;
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }

  void _onSafeModeChanged() {
    if (!SafeBoot.instance.safeMode.value) return;
    NeuraAiService.instance.cancelActiveGeneration();
    unawaited(_suspendOptionalRuntime());
  }

  /// Best-effort shutdown for optional work if Safe Mode is enabled from
  /// Diagnostics after a normal boot. Initial Safe Mode never starts these
  /// services in the first place.
  Future<void> _suspendOptionalRuntime() async {
    await Future.wait<void>([
      AmbientListeningService.instance.stop().catchError((_) {}),
      WakeWordListenerService.instance.stop().catchError((_) {}),
      if (_notificationsStarted)
        NeuraNotificationsService.instance.cancelAll().catchError((_) {}),
      if (_runtimeStarted)
        NeuraRuntimeController.I.dispose().catchError((_) {}),
      if (_swarmStarted)
        NeuraSwarmService.instance.clearCredential().catchError((_) {}),
    ]);
    _notificationsStarted = false;
    _runtimeStarted = false;
    _swarmStarted = false;
  }

  void _emit(String label, double progress) {
    stage.value = NeuraBootStage(label, progress);
    debugPrint(
      '[NeuraStartup] ${(progress * 100).toStringAsFixed(0).padLeft(3)}% $label',
    );
  }
}
