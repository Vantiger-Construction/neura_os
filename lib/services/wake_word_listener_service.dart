import 'dart:async';

import '../core/memory/memory_graph_service.dart';
import '../core/neura_event_bus.dart';
import '../core/neura_events.dart';
import '../mascot/mascot_window_service.dart';
import '../modules/core/app_log.dart';
import '../persona/agents/agent_persona_catalog.dart';
import '../reliability/safe_boot.dart';
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
  WakeWordListenerService._() {
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }
  static final WakeWordListenerService instance = WakeWordListenerService._();

  static final RegExp _wakePattern =
      RegExp(r'^\s*(hey\s+)?neura\b[,.]?\s*', caseSensitive: false);

  NeuraSpeechToTextService? _stt;
  StreamSubscription<String>? _sub;
  bool _awaitingMessageAfterWake = false;
  bool _busy = false;
  bool _weStartedSession = false;
  int _dataGeneration = 0;
  Future<void>? _activeTurn;
  bool get listeningAllowed => !SafeBoot.instance.safeMode.value;

  /// Begins listening if the feature is enabled. Safe to call more than
  /// once (no-ops if already subscribed).
  Future<void> start() async {
    if (!listeningAllowed) return;
    if (!WakeWordPrefsController.instance.enabled.value) return;
    if (_sub != null) return;
    await _beginListening();
  }

  Future<void> stop() async {
    final wasListening = _sub != null;
    await _sub?.cancel();
    _sub = null;
    _awaitingMessageAfterWake = false;
    final stt = _stt;
    if (_weStartedSession && stt != null && stt.isListening) {
      await stt.stopRecording();
    }
    _weStartedSession = false;
    if (wasListening) NeuraEventBus.I.emit(const NeuraListeningEvent(false));
  }

  Future<void> resetAfterDataWipe() async {
    _dataGeneration += 1;
    await stop();
    final activeTurn = _activeTurn;
    if (activeTurn != null) {
      try {
        await activeTurn;
      } catch (_) {
        // The normal turn handler already records/degrades its own failures.
      }
    }
  }

  /// Suspends reacting to phrases without stopping the underlying session,
  /// for as long as another feature (the chat screen's own mic button) owns
  /// the shared [NeuraSpeechToTextService] — avoids double-processing the
  /// same phrases through two different listeners at once.
  void pause() {
    final wasListening = _sub != null;
    _sub?.cancel();
    _sub = null;
    _awaitingMessageAfterWake = false;
    if (wasListening) NeuraEventBus.I.emit(const NeuraListeningEvent(false));
  }

  Future<void> resume() async {
    if (!listeningAllowed) return;
    if (!WakeWordPrefsController.instance.enabled.value) return;
    if (_sub != null) return;
    await _beginListening();
  }

  Future<void> _beginListening() async {
    if (!listeningAllowed) return;
    final stt = _stt ??= NeuraSpeechToTextService.instance;
    if (!stt.isListening) {
      // Wait for the mascot window's own native engine/window creation to
      // settle first as a best-effort plugin startup barrier. This ordering
      // does not fix issue #32: its native TTS crash reproduced without a
      // mascot window. Keep the independent microphone ordering precaution.
      // Already-resolved after the first real boot, so this is a no-op on
      // pause()/resume() cycles.
      await MascotWindowService.I.initialCreationSettled;
      if (!listeningAllowed) return;
      final ok = await stt.startRecording();
      if (!ok) return;
      if (!listeningAllowed) {
        await stt.stopRecording();
        return;
      }
      _weStartedSession = true;
    }
    if (!listeningAllowed) return;
    _sub = stt.finalPhraseStream.listen(_onFinalPhrase);
    NeuraEventBus.I.emit(const NeuraListeningEvent(true));
  }

  void _onFinalPhrase(String phrase) {
    if (_busy || !listeningAllowed) return;
    final trimmed = phrase.trim();
    if (trimmed.isEmpty) return;

    if (_awaitingMessageAfterWake) {
      _awaitingMessageAfterWake = false;
      _startMessage(trimmed);
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
    _startMessage(remainder);
  }

  void _startMessage(String text) {
    if (!listeningAllowed) return;
    final turn = _handleMessage(text);
    _activeTurn = turn;
    unawaited(
      turn.whenComplete(() {
        if (identical(_activeTurn, turn)) _activeTurn = null;
      }).catchError((_) {}),
    );
  }

  Future<void> _handleMessage(String text) async {
    if (!listeningAllowed) return;
    final generation = _dataGeneration;
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
      if (generation != _dataGeneration) return;

      final reply = buffer.toString();
      unawaited(_remember(isUser: true, text: text));
      unawaited(_remember(isUser: false, text: reply));

      NeuraEventBus.I.emit(const NeuraTalkingEvent(true));
      await NeuraTtsService.instance.speak(reply);
    } catch (e, st) {
      await AppLog.instance.caught('wake_word_reply_failed', e, st);
    } finally {
      NeuraEventBus.I.emit(const NeuraThinkingEvent(false));
      NeuraEventBus.I.emit(const NeuraTalkingEvent(false));
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
    } catch (e, st) {
      await AppLog.instance.caught('wake_word_memory_log_failed', e, st);
    }
  }

  void _onSafeModeChanged() {
    if (!listeningAllowed) {
      unawaited(stop().catchError((_) {}));
    }
  }
}
