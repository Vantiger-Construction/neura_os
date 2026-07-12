import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../avatar/avatar_controller.dart';
import 'neura_error_vault.dart';
import 'neura_event_bus.dart';
import 'neura_fault_event.dart';

/// Installs global crash hooks + a friendly error UI + Dimensional Sync recovery trigger.
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

    // 1) Friendly error widget (replaces red screen)
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return _NeuraFriendlyError(
        details: details,
        message: userFacingMessage,
      );
    };

    // 2) Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);

      final event = NeuraFaultEvent(
        message: details.exceptionAsString(),
        stack: details.stack?.toString(),
        source: 'FlutterError',
      );

      _handle(bus, controller, event, recoveryDuration);
    };

    // 3) Platform dispatcher (uncaught async errors)
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      final event = NeuraFaultEvent(
        message: error.toString(),
        stack: stack.toString(),
        source: 'PlatformDispatcher',
      );

      _handle(bus, controller, event, recoveryDuration);
      return true; // we handled it
    };

    // Restore builder on hot restart? Not needed; builder stays active for this process.
    unawaited(Future<void>.value());
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

    Future<void>.delayed(dur).then((_) {
      try {
        controller.setError(false);
      } catch (_) {}
    });
  }
}

class _NeuraFriendlyError extends StatelessWidget {
  final FlutterErrorDetails details;
  final String message;

  const _NeuraFriendlyError({
    required this.details,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData.dark();
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DefaultTextStyle(
            style: theme.textTheme.bodyMedium ??
                const TextStyle(color: Colors.white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Neura Recovery Mode',
                  style: (theme.textTheme.headlineSmall ??
                          const TextStyle(fontSize: 20))
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(message),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  details.exceptionAsString(),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        // Open details dialog
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Details'),
                            content: SingleChildScrollView(
                              child: Text(
                                details.toString(),
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('Show details'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () async {
                        final p = await NeuraErrorVault.getVaultPath();
                        if (!context.mounted) return;
                        final snack = SnackBar(
                          content: Text(p == null
                              ? 'Vault not available on this platform.'
                              : 'Vault: $p'),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(snack);
                      },
                      child: const Text('Vault path'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
