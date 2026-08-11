import 'dart:async';

import '../core/memory/memory_graph_service.dart';
import '../core/neura_event_bus.dart';
import '../core/neura_events.dart';
import '../mascot/mascot_window_service.dart';
import '../modules/core/app_log.dart';
import '../persona/agents/agent_persona_catalog.dart';
import 'neura_ai_service.dart';
import 'neura_speech_to_text_service.dart';
import 'neura_tts_service.dart';
import 'wake_word_prefs.dart';

/// Hands-free "Hey Neura" wake phrase — watches the shared continuous
/// dictation session for a phrase starting with the wake word, and if one
/// is heard, sends whatever follows (or, if the wake word was said alone,
/// the *next* completed phrase) to Neura as a chat turn, speaking the reply.
///
/// Deliberately gates on the wake phrase before sending anything to the
/// API: [NeuraSpeechToTextService] is a continuous recognizer, so without
/// this gate every phrase said anywhere near the mic would otherwise ship
/// straight to Claude.
class WakeWordListenerService {
  WakeWordListenerService._();
  static final WakeWordListenerService instance = WakeWordListenerService._();

  static final RegExp _wakePattern =
      RegExp(r'^\s*(hey\s+)?neura\b[,.]?\s*', caseSensitive: false);

  final NeuraSpeechToTextService _stt = NeuraSpeechToTextService.instance;
  StreamSubscription<String>? _sub;
  bool _awaitingMessageAfterWake = false;
  bool _busy = false;
  bool _weStartedSession = false;

  /// Begins listening if the feature is enabled. Safe to call more than
  /// once (no-ops if already subscribed).
  Future<void> start() async {
    if (!WakeWordPrefsController.instance.enabled.value) return;
    if (_sub != null) return;
    await _beginListening();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _awaitingMessageAfterWake = false;
    if (_weStartedSession && _stt.isListening) {
      await _stt.stopRecording();
    }
    _weStartedSession = false;
  }

  /// Suspends reacting to phrases without stopping the underlying session,
  /// for as long as another feature (the chat screen's own mic button) owns
  /// the shared [NeuraSpeechToTextService] — avoids double-processing the
  /// same phrases through two different listeners at once.
  void pause() {
    _sub?.cancel();
    _sub = null;
    _awaitingMessageAfterWake = false;
  }

  Future<void> resume() async {
    if (!WakeWordPrefsController.instance.enabled.value) return;
    if (_sub != null) return;
    await _beginListening();
  }

  Future<void> _beginListening() async {
    if (!_stt.isListening) {
      // Wait for the mascot window's own native engine/window creation to
      // settle first -- same "two native engines/windows starting close
      // together" hazard documented on MascotWindowService.initialCreationSettled
      // and already worked around in AmbientListeningService.greetAndStartListening
      // for the TTS path; this is the same wait for the wake-word mic path.
      // Already-resolved after the first real boot, so this is a no-op on
      // pause()/resume() cycles.
      await MascotWindowService.I.initialCreationSettled;
      final ok = await _stt.startRecording();
      if (!ok) return;
      _weStartedSession = true;
    }
    _sub = _stt.finalPhraseStream.listen(_onFinalPhrase);
  }

  void _onFinalPhrase(String phrase) {
    if (_busy) return;
    final trimmed = phrase.trim();
    if (trimmed.isEmpty) return;

    if (_awaitingMessageAfterWake) {
      _awaitingMessageAfterWake = false;
      unawaited(_handleMessage(trimmed));
      return;
    }

    final match = _wakePattern.firstMatch(trimmed);
    if (match == null) return; // Not addressed to Neura -- ignore.

    final remainder = trimmed.substring(match.end).trim();
    if (remainder.isEmpty) {
      // Just "Hey Neura" -- wait for the next completed phrase as the
      // actual message.
      _awaitingMessageAfterWake = true;
      return;
    }
    unawaited(_handleMessage(remainder));
  }

  Future<void> _handleMessage(String text) async {
    _busy = true;
    NeuraEventBus.I.emit(const NeuraThinkingEvent(true));
    try {
      final buffer = StringBuffer();
      await for (final delta in NeuraAiService.instance.streamReply(
        [NeuraChatTurn(isUser: true, text: text)],
        agentId: AgentPersonaCatalog.generalId,
      )) {
        buffer.write(delta);
      }
      final reply = buffer.toString();
      NeuraEventBus.I.emit(const NeuraThinkingEvent(false));
      unawaited(_remember(isUser: true, text: text));
      unawaited(_remember(isUser: false, text: reply));

      NeuraEventBus.I.emit(const NeuraTalkingEvent(true));
      await NeuraTtsService.instance.speak(reply);
      NeuraEventBus.I.emit(const NeuraTalkingEvent(false));
    } catch (e) {
      NeuraEventBus.I.emit(const NeuraThinkingEvent(false));
      await AppLog.instance.warn('wake_word_reply_failed: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _remember({required bool isUser, required String text}) async {
    if (text.trim().isEmpty) return;
    try {
      if (isUser) {
        await MemoryGraphService.I.logUserAction(
          kind: 'CHAT_MESSAGE',
          payload: {'text': text, 'source': 'wake_word'},
        );
      } else {
        await MemoryGraphService.I.logSuggestion(
          kind: 'CHAT_REPLY',
          payload: {'text': text, 'source': 'wake_word'},
        );
      }
    } catch (e) {
      await AppLog.instance.warn('wake_word_memory_log_failed: $e');
    }
  }
}
