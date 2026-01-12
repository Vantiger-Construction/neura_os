import 'package:flutter/material.dart';

import '../../modules/human/human_prefs_controller.dart';
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
      builder: (context, shellPrefs, _) {
        return ValueListenableBuilder(
          valueListenable: HumanPrefsController.instance.prefs,
          builder: (context, humanPrefs, __) {
            final fxOn = shellPrefs.ambientFx &&
                !humanPrefs.reducedMotion &&
                !humanPrefs.lowStim &&
                !humanPrefs.safeMode;
            return Stack(
              children: [
                Positioned.fill(child: AmbientFx(enabled: fxOn)),
                Positioned.fill(child: child),
                Align(
                  alignment: Alignment.topCenter,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: _FocusBanner(),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _FocusBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(); // Placeholder
  }
}
