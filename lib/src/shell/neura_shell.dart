import 'package:flutter/material.dart';

import '../modules/focus/focus_controller.dart';
import '../modules/focus/focus_mode.dart';
import 'ambient_fx.dart';
import 'shell_prefs.dart';

/// Global OS shell wrapper.
///
/// Adds:
/// - Ambient background FX
/// - Focus Mode banner
///
/// It wraps the MaterialApp's navigator via `MaterialApp.builder`.
class NeuraShell extends StatelessWidget {
  final Widget child;
  const NeuraShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ShellPrefsController.instance.prefs,
      builder: (context, prefs, _) {
        return Stack(
          children: [
            Positioned.fill(child: AmbientFx(enabled: prefs.ambientFx)),
            Positioned.fill(child: child),
            Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: _FocusBanner(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FocusBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: FocusController.instance.state,
      builder: (context, state, _) {
        if (state.mode == FocusMode.off) return const SizedBox.shrink();

        final accent = state.mode.accent ?? Theme.of(context).colorScheme.primary;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.black.withOpacity(0.35),
            border: Border.all(color: accent.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(state.mode.icon, color: accent),
              const SizedBox(width: 8),
              Text(
                '${state.mode.label} Mode',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => FocusController.instance.setMode(FocusMode.off),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 18, color: Colors.white.withOpacity(0.75)),
                ),
              )
            ],
          ),
        );
      },
    );
  }
}
