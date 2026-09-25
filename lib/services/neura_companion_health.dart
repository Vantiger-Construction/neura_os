import 'package:flutter/foundation.dart';

import '../avatar/avatar_globals.dart';
import '../avatar/neura_avatar_runtime_bridge.dart';
import '../reliability/safe_boot.dart';
import '../src/shell/shell_prefs.dart';
import 'neura_ai_service.dart';
import 'neura_device_continuity_service.dart';
import 'neura_llm_diagnostics.dart';
import 'neura_tts_service.dart';

enum NeuraCompanionHealthLevel { healthy, protected, information }

@immutable
class NeuraCompanionHealthCheck {
  const NeuraCompanionHealthCheck({
    required this.id,
    required this.title,
    required this.detail,
    required this.level,
  });

  final String id;
  final String title;
  final String detail;
  final NeuraCompanionHealthLevel level;
}

@immutable
class NeuraCompanionHealthSnapshot {
  const NeuraCompanionHealthSnapshot(this.checks);

  final List<NeuraCompanionHealthCheck> checks;

  int get protectedCount => checks
      .where((check) => check.level == NeuraCompanionHealthLevel.protected)
      .length;

  /// Collects bounded operational labels only. No conversation, memory,
  /// journal, prompt, credential, device identity, or file path is included.
  factory NeuraCompanionHealthSnapshot.collect() {
    final safeMode = SafeBoot.instance.safeMode.value;
    final speechMode = NeuraTtsService.instance.replySpeechMode;
    final continuity = NeuraDeviceContinuityService.instance.snapshot;
    final avatar = NeuraAvatarRuntimeBridge.instance.snapshot.value;
    final llm = NeuraLlmDiagnostics.instance.snapshot();
    final shell = ShellPrefsController.instance.prefs.value;
    final modelConfigured = NeuraAiService.instance.isConfigured;

    return NeuraCompanionHealthSnapshot(<NeuraCompanionHealthCheck>[
      NeuraCompanionHealthCheck(
        id: 'safety',
        title: safeMode ? 'Safe Mode protection' : 'Safety boundaries',
        detail: safeMode
            ? 'Microphone, automatic voice, and cloud access are off.'
            : 'Cloud requests still require a fresh visible approval.',
        level: safeMode
            ? NeuraCompanionHealthLevel.protected
            : NeuraCompanionHealthLevel.healthy,
      ),
      NeuraCompanionHealthCheck(
        id: 'voice',
        title: 'Conversational voice',
        detail: safeMode
            ? 'Disabled by Safe Mode.'
            : speechMode == NeuraReplySpeechMode.off
                ? 'Automatic reply speech is off by choice.'
                : '${speechMode.label}; microphone use remains foreground-only.',
        level: safeMode
            ? NeuraCompanionHealthLevel.protected
            : NeuraCompanionHealthLevel.healthy,
      ),
      NeuraCompanionHealthCheck(
        id: 'intelligence',
        title: 'Intelligence route',
        detail: modelConfigured && !safeMode
            ? 'On-device fallback plus approval-gated model routing.'
            : 'Deterministic on-device fallback is ready.',
        level: safeMode
            ? NeuraCompanionHealthLevel.protected
            : (llm['healthy'] == false
                ? NeuraCompanionHealthLevel.information
                : NeuraCompanionHealthLevel.healthy),
      ),
      const NeuraCompanionHealthCheck(
        id: 'memory',
        title: 'Consent-scoped memory',
        detail: 'Reply receipts disclose context categories without content. '
            'Private-room and journaling policies remain local authority.',
        level: NeuraCompanionHealthLevel.healthy,
      ),
      const NeuraCompanionHealthCheck(
        id: 'actions',
        title: 'Safe action plans',
        detail: 'Each side-effect step keeps its own review, fresh approval, '
            'execution check, and undo boundary.',
        level: NeuraCompanionHealthLevel.healthy,
      ),
      NeuraCompanionHealthCheck(
        id: 'continuity',
        title: 'Windows–Android handoff',
        detail: continuity.handoffReady
            ? '${continuity.activeDevices} active paired devices; signed, '
                'encrypted handoff previews are available.'
            : 'Pair two trusted devices to enable signed, encrypted handoff.',
        level: continuity.privateRecordsRemainLocal
            ? NeuraCompanionHealthLevel.healthy
            : NeuraCompanionHealthLevel.protected,
      ),
      NeuraCompanionHealthCheck(
        id: 'avatar',
        title: 'Room presence and avatar bridge',
        detail: avatar == null
            ? 'The content-free avatar bridge starts with the main shell.'
            : '${AvatarGlobals.service.selectedAvatarId.value} is in '
                '${avatar.roomId}; motion is ${avatar.motion.name}.',
        level: avatar?.safeMode == true ||
                shell.companionMotion == NeuraCompanionMotion.still
            ? NeuraCompanionHealthLevel.protected
            : NeuraCompanionHealthLevel.healthy,
      ),
    ]);
  }
}
