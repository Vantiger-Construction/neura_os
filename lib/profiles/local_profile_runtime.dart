import '../avatar/motion/neura_motion.dart';
import '../encrypted_memory/companion_memory_service.dart';
import '../mascot/mascot_window_service.dart';
import '../neura_runtime/neura_runtime_controller.dart';
import '../notifications/neura_notifications_service.dart';
import '../services/ambient_listening_service.dart';
import '../services/neura_ai_service.dart';
import '../services/neura_local_speech_input.dart';
import '../services/neura_speech_to_text_service.dart';
import '../services/neura_tts_service.dart';
import '../services/neura_voice_pack.dart';
import '../services/voice_journal_service.dart';
import '../services/sleep_listener_service.dart';
import '../services/wake_word_listener_service.dart';
import '../modules/vault/vault_session.dart';

abstract final class LocalProfileRuntime {
  static Future<void> stop() async {
    NeuraAiService.instance.cancelActiveGeneration();
    CompanionMemoryService.revokeAllForProfileBoundary();
    VaultSession.lock();
    NeuraMotion.instance.engine.setMood(0, 0.5);
    // Attempt every shutdown; activation fails if any owner cannot stop.
    final results = await Future.wait([
      _attempt(NeuraLocalSpeechInput.instance.shutdownForDataWipe),
      _attempt(NeuraSpeechToTextService.instance.shutdownForProfiles),
      _attempt(VoiceJournalService.shutdownAllForProfiles),
      _attempt(NeuraVoicePack.I.stopMic),
      _attempt(NeuraVoicePack.I.stop),
      _attempt(AmbientListeningService.instance.resetAfterDataWipe),
      _attempt(WakeWordListenerService.instance.resetAfterDataWipe),
      _attempt(NeuraTtsService.instance.stop),
      _attempt(SleepListenerService.stopAllForProfiles),
      _attempt(NeuraRuntimeController.I.resetAfterDataWipe),
      _attempt(NeuraNotificationsService.instance.cancelAllForSafeMode),
    ]);
    // The separate mascot engine cannot inherit a selected profile's style.
    await MascotWindowService.I.suspendForProfiles();
    if (results.contains(false)) {
      throw StateError('Session shutdown unconfirmed.');
    }
  }

  static Future<bool> _attempt(Future<void> Function() operation) async {
    try {
      await operation().timeout(const Duration(seconds: 5));
      return true;
    } catch (_) {
      return false;
    }
  }
}
