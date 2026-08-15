import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../avatar/avatar_globals.dart';
import '../avatar/avatar_orchestrator.dart';
import '../avatar/avatar_orchestrator_viseme_ext.dart';
import '../config/supabase_config.dart';
import '../core/neura_event_bus.dart';
import '../modules/core/app_log.dart';
import '../modules/core/error_handler.dart';
import '../modules/human/human_prefs_controller.dart';
import '../modules/humor/joke_prefs_controller.dart';
import '../neura_runtime/neura_runtime_controller.dart';
import '../services/ambient_listening_prefs.dart';
import '../services/wake_word_prefs.dart';
import '../notifications/neura_notifications_prefs.dart';
import '../notifications/neura_notifications_service.dart';
import '../services/app_lock_prefs.dart';
import '../services/neura_swarm_service.dart';
import '../services/neura_provider_credentials.dart';
import '../services/neura_tts_service.dart';
import '../services/neura_voice_pack.dart';
import '../reliability/module_health_monitor.dart';
import '../reliability/safe_boot.dart';
import '../reliability/timeline_vault.dart';
import '../src/modules/focus/focus_controller.dart';
import '../src/shell/shell_prefs.dart';
/// One stage in the startup sequence (label + 0.0–1.0 progress).
import 'neura_prefs_cache.dart';

class NeuraBootStage {
  final String label;
  final double progress;
  const NeuraBootStage(this.label, this.progress);
}

/// Owns the complete Neura boot sequence.
///
/// Call [boot] once (fire-and-forget from main or NeuraBootScreen).
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

  bool _booted = false;

  /// Current boot stage (label + fraction progress).
  final ValueNotifier<NeuraBootStage> stage =
      ValueNotifier(const NeuraBootStage('Initializing…', 0.0));

  /// Flips to true once boot completes (even if some non-fatal steps failed).
  final ValueNotifier<bool> ready = ValueNotifier(false);

  /// Runs the full startup sequence. Subsequent calls are no-ops.
  Future<void> boot() async {
    if (_booted) return;
    _booted = true;

    // Safe Boot marker is written before native services start. If two
    // consecutive launches fail to reach completeBoot(), optional native and
    // network services are skipped on the next launch.
    try {
      await SafeBoot.instance.beginBoot();
      ModuleHealthMonitor.instance.healthy('SafeBoot');
    } catch (error) {
      ModuleHealthMonitor.instance.failed('SafeBoot', error);
    }

    // 1 – Error handler (synchronous, must be first)
    _emit('Setting up error handling…', 0.05);
    ErrorHandler.install();

    // 2 – Logging
    _emit('Starting logger…', 0.10);
    await _safe(AppLog.instance.init, 'AppLog');
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
    await _safe(NeuraPrefsCache.init, 'PrefsCache');

    // 4 – OS-level shell state
    _emit('Loading shell settings…', 0.30);
    await _safe(ShellPrefsController.instance.init, 'ShellPrefs');
    await _safe(FocusController.instance.init, 'FocusController');
    await _safe(HumanPrefsController.instance.init, 'HumanPrefs');
    await _safe(AppLockPrefsController.instance.init, 'AppLockPrefs');
    await _safe(JokePrefsController.instance.init, 'JokePrefs');
    await _safe(AmbientListeningPrefsController.instance.init, 'AmbientListeningPrefs');
    await _safe(WakeWordPrefsController.instance.init, 'WakeWordPrefs');
    await _safe(NeuraNotificationsPrefsController.instance.init, 'NotificationsPrefs');
    if (SafeBoot.instance.safeMode.value) {
      ModuleHealthMonitor.instance.skipped(
        'NotificationsService',
        'Safe Mode disables optional native services.',
      );
    } else {
      await _safe(NeuraNotificationsService.instance.init, 'NotificationsService');
    }

    // 5 – Avatar runtime (in-memory, essentially instant)
    _emit('Waking Neura avatar…', 0.50);
    _startAvatarRuntime();

    // 6 – Voice (mic capture is started lazily by whichever screen needs it,
    // e.g. VoiceLabScreen's mic toggle — not held open continuously from boot).
    _emit('Preparing voice…', 0.65);
    if (!SafeBoot.instance.safeMode.value) {
      await _safe(() => NeuraVoicePack.I.init(enableMic: false), 'VoicePack');
    } else {
      ModuleHealthMonitor.instance.skipped('VoicePack', 'Disabled by Safe Mode.');
    }
    // Forces flutter_tts's native engine to initialize now, while nothing
    // else native is starting up yet -- root-caused via crash reproduction
    // (Windows Error Reporting: flutter_tts_plugin.dll, exception
    // 0xC0000005, 100% reproducible) that this native init crashing the
    // whole process when it happens to be the *first* TTS call AND the
    // mascot window's own separate engine is concurrently spinning up (see
    // MascotWindowService, which only starts once `ready` below flips true
    // -- strictly after this line). By the time AmbientListeningService's
    // proactive greeting calls speak() later, the engine is already warm
    // and this is no longer that first, fragile call. A Dart try/catch
    // around the later speak() call was never able to prevent this -- a
    // native access violation kills the process outright, it isn't
    // something Dart exception handling can intercept.
    if (!SafeBoot.instance.safeMode.value) {
      await _safe(() => NeuraTtsService.instance.warmUp(), 'TtsWarmup');
    } else {
      ModuleHealthMonitor.instance.skipped('TtsWarmup', 'Disabled by Safe Mode.');
    }

    // 6b – Provider credential + Rust swarm. Existing build-time credentials
    // are migrated once into OS-backed secure storage. New builds should not
    // contain provider secrets.
    await _safe(
      NeuraProviderCredentials.instance.initialize,
      'ProviderCredentials',
    );
    await _safe(
      () => NeuraSwarmService.instance
          .init(NeuraProviderCredentials.instance.apiKey),
      'SwarmInit',
    );

    // 7 – Room / memory runtime
    _emit('Loading memory…', 0.80);
    await _safe(NeuraRuntimeController.I.start, 'NeuraRuntime');

    // 8 – Supabase (network, last + optional; gracefully skipped if placeholder keys)
    _emit('Connecting to cloud…', 0.90);
    if (!SafeBoot.instance.safeMode.value) {
      await _safe(_initSupabase, 'Supabase');
    } else {
      ModuleHealthMonitor.instance.skipped('Supabase', 'Disabled by Safe Mode.');
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
  Future<void> _safe(Future<void> Function() fn, String label) async {
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
    } catch (e, st) {
      stopwatch.stop();
      ModuleHealthMonitor.instance.failed(label, e);
      debugPrint('[NeuraStartup] $label failed (non-fatal): $e\n$st');
      try {
        await TimelineVault.instance.append('module_failed', data: {
          'module': label,
          'error_type': e.runtimeType.toString(),
        });
      } catch (_) {}
      try {
        await AppLog.instance.warn('startup.$label failed: $e');
      } catch (_) {}
    }
  }

  void _emit(String label, double progress) {
    stage.value = NeuraBootStage(label, progress);
    debugPrint(
      '[NeuraStartup] ${(progress * 100).toStringAsFixed(0).padLeft(3)}% $label',
    );
  }
}
