import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lightweight recovery controls: no preferences, network or log-file reads.
/// The export is a previewed content-free summary, never raw exception text.
class NeuraBootRecoveryActions extends StatelessWidget {
  const NeuraBootRecoveryActions({
    super.key,
    required this.onRetry,
    required this.onSafeMode,
    required this.safeMode,
    required this.module,
    this.busy = false,
  });

  final VoidCallback onRetry;
  final VoidCallback onSafeMode;
  final bool safeMode;
  final String module;
  final bool busy;

  String get summary {
    const allowedModules = {'PrefsCache', 'StartupCoordinator'};
    final safeModule = allowedModules.contains(module) ? module : 'unknown';
    return 'Neura startup recovery v1\n'
        'module: $safeModule\n'
        'safe_mode: $safeMode\n'
        'startup_complete: false\n'
        'No chat, journal, file path, credential or exception text included.';
  }

  Future<void> _showSummary(BuildContext context) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Startup summary'),
          scrollable: true,
          content: SelectableText(summary),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: summary));
                  if (context.mounted) Navigator.pop(context);
                } catch (_) {
                  // A missing clipboard must not break recovery. Selectable
                  // text remains available for an explicit manual copy.
                }
              },
              child: const Text('Copy summary'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: busy ? null : onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry startup'),
          ),
          if (!safeMode)
            OutlinedButton.icon(
              onPressed: busy ? null : onSafeMode,
              icon: const Icon(Icons.health_and_safety_outlined),
              label: const Text('Retry in Safe Mode'),
            ),
          TextButton.icon(
            onPressed: () => _showSummary(context),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Preview startup summary'),
          ),
        ],
      );
}
