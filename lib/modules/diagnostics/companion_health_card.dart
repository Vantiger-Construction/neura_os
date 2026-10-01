import 'package:flutter/material.dart';

import '../../avatar/avatar_globals.dart';
import '../../avatar/neura_avatar_runtime_bridge.dart';
import '../../reliability/safe_boot.dart';
import '../../services/neura_companion_health.dart';
import '../../services/neura_tts_service.dart';
import '../../src/shell/shell_prefs.dart';

class NeuraCompanionHealthCard extends StatelessWidget {
  const NeuraCompanionHealthCard({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        SafeBoot.instance.safeMode,
        ShellPrefsController.instance.prefs,
        AvatarGlobals.service.selectedAvatarId,
        NeuraAvatarRuntimeBridge.instance.snapshot,
      ]),
      builder: (context, _) {
        final health = NeuraCompanionHealthSnapshot.collect();
        return Card(
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Companion health'),
            subtitle: Text(
              '${health.checks.length} content-free checks · '
              '${NeuraTtsService.instance.replySpeechMode.label}',
            ),
            children: <Widget>[
              for (final check in health.checks)
                ListTile(
                  dense: true,
                  leading: Icon(
                    switch (check.level) {
                      NeuraCompanionHealthLevel.healthy =>
                        Icons.check_circle_outline,
                      NeuraCompanionHealthLevel.protected =>
                        Icons.shield_outlined,
                      NeuraCompanionHealthLevel.information =>
                        Icons.info_outline,
                    },
                    color: switch (check.level) {
                      NeuraCompanionHealthLevel.healthy => Colors.green,
                      NeuraCompanionHealthLevel.protected => Colors.blue,
                      NeuraCompanionHealthLevel.information => Colors.orange,
                    },
                  ),
                  title: Text(check.title),
                  subtitle: Text(check.detail),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(
                  'Health checks contain operational labels only. They do not '
                  'read or export conversation, memory, journal, credential, '
                  'device-identity, or file content.',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
