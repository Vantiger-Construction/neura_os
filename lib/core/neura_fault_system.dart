import 'dart:async';

import '../avatar/avatar_controller.dart';
import '../startup/neura_error_pipeline.dart';
import 'neura_error_vault.dart';
import 'neura_event_bus.dart';
import 'neura_fault_event.dart';

/// Adapts the process-wide error pipeline to avatar and event-bus recovery.
///
/// Zero new deps. Safe if avatar inputs/assets are missing.
class NeuraFaultSystem {
  static bool _installed = false;

  static const String defaultUserFacingMessage =
      "Dimensional Sync engaged. Your multiversal twin already debugged this. You're welcome.";

  static void install({
    required NeuraEventBus bus,
    required AvatarController controller,
    String userFacingMessage = defaultUserFacingMessage,
    Duration recoveryDuration = const Duration(seconds: 2),
  }) {
    if (_installed) return;
    _installed = true;

    final pipeline = NeuraErrorPipeline.instance;
    pipeline.installGlobalHandlers();
    pipeline.addObserver((payload) {
      final event = NeuraFaultEvent(
        message: payload['message']?.toString() ?? userFacingMessage,
        stack: payload['stack']?.toString(),
        source: '${payload['source'] ?? 'unknown'} '
            '(${payload['phase'] ?? 'runtime'})',
      );
      _handle(bus, controller, event, recoveryDuration);
    });
  }

  static void _handle(
    NeuraEventBus bus,
    AvatarController controller,
    NeuraFaultEvent event,
    Duration recoveryDuration,
  ) {
    // Emit event for the rest of the system
    bus.emit(event);

    // Vault it (best-effort)
    unawaited(NeuraErrorVault.append(event));

    // Drive avatar recovery (best-effort, never throws)
    _pulseAvatar(controller, recoveryDuration);
  }

  static void _pulseAvatar(AvatarController controller, Duration dur) {
    try {
      controller.setError(true);
      controller.pulseBlink();
      controller.pulseWave();
    } catch (_) {
      // ignore
    }

    unawaited(
      Future<void>.delayed(dur).then((_) {
        try {
          controller.setError(false);
        } catch (_) {}
      }),
    );
  }
}
