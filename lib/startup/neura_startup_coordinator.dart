import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../avatar/avatar_globals.dart';
import '../avatar/avatar_orchestrator.dart';
import '../avatar/avatar_orchestrator_viseme_ext.dart';
import '../config/supabase_config.dart';
import '../core/neura_event_bus.dart';
import '../modules/core/app_log.dart';
import '../modules/core/error_handler.dart';
import '../neura_runtime/neura_runtime_controller.dart';
import '../services/neura_voice_pack.dart';
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

    // 1 – Error handler (synchronous, must be first)
    _emit('Setting up error handling…', 0.05);
    ErrorHandler.install();

    // 2 – Logging
    _emit('Starting logger…', 0.10);
    await _safe(AppLog.instance.init, 'AppLog');

    // 3 – SharedPreferences (single cached instance used by all services)
    _emit('Loading preferences…', 0.20);
    await _safe(NeuraPrefsCache.init, 'PrefsCache');

    // 4 – OS-level shell state
    _emit('Loading shell settings…', 0.30);
    await _safe(ShellPrefsController.instance.init, 'ShellPrefs');
    await _safe(FocusController.instance.init, 'FocusController');

    // 5 – Avatar runtime (in-memory, essentially instant)
    _emit('Waking Neura avatar…', 0.50);
    _startAvatarRuntime();

    // 6 – Voice / mic (audio hardware – may be slow or permission-denied)
    _emit('Connecting microphone…', 0.65);
    await _safe(() => NeuraVoicePack.I.init(enableMic: true), 'VoicePack');

    // 7 – Room / memory runtime
    _emit('Loading memory…', 0.80);
    await _safe(NeuraRuntimeController.I.start, 'NeuraRuntime');

    // 8 – Supabase (network, last + optional; gracefully skipped if placeholder keys)
    _emit('Connecting to cloud…', 0.90);
    await _safe(_initSupabase, 'Supabase');

    // Done
    _emit('Ready!', 1.0);
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
    if (SupabaseConfig.url.startsWith('YOUR_') ||
        SupabaseConfig.anonKey.startsWith('YOUR_')) {
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
    try {
      await fn();
    } catch (e, st) {
      debugPrint('[NeuraStartup] $label failed (non-fatal): $e\n$st');
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
