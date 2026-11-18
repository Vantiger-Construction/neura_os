import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../reliability/safe_boot.dart';
import 'neura_local_speech_input.dart';
import 'neura_startup_voice_prefs.dart';
import 'neura_tts_service.dart';

/// Shared, explicit opt-in flow for "listen when Neura opens".
///
/// Used by Voice settings and by Neura's corner in the menu so both apply the
/// same checks: an on-device speech pack, microphone permission where the OS
/// asks for it, and no Safe Mode or pending restart.
class NeuraStartupVoiceSetup {
  NeuraStartupVoiceSetup._();

  /// Whether this platform supports the startup-voice opt-in at all.
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Whether the opt-in can be changed right now.
  static bool get canChange =>
      supported &&
      !SafeBoot.instance.safeMode.value &&
      !SafeBoot.instance.restartRequired.value;

  /// Saves the opt-in. Throws a [StateError] with a user-facing message when
  /// it cannot be enabled. [stillWanted] lets the caller abandon the change if
  /// its UI went away while permission prompts were open.
  static Future<void> setEnabled(
    bool value, {
    bool Function()? stillWanted,
  }) async {
    if (value) {
      if (!await NeuraLocalSpeechInput.instance.isAvailable()) {
        throw StateError('Install an on-device speech language pack first.');
      }
      if (defaultTargetPlatform == TargetPlatform.android &&
          !(await Permission.microphone.request()).isGranted) {
        throw StateError('Allow microphone access to use startup voice.');
      }
      if (!(stillWanted?.call() ?? true) ||
          SafeBoot.instance.safeMode.value ||
          SafeBoot.instance.restartRequired.value) {
        return;
      }
      await NeuraTtsService.instance.prepareLocalStartupVoice();
    }
    await NeuraStartupVoicePrefs.instance.setEnabled(value);
    if (value &&
        NeuraTtsService.instance.replySpeechMode == NeuraReplySpeechMode.off) {
      await NeuraTtsService.instance
          .setReplySpeechMode(NeuraReplySpeechMode.afterComplete);
    }
  }
}
