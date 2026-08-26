import 'private_neural_core.dart';
import 'presence_engine.dart';

class NeuraTurnLimits {
  const NeuraTurnLimits({
    this.maximumDeltaCharacters = 2048,
    this.maximumTotalCharacters = 12000,
    this.maximumDeltas = 512,
  })  : assert(maximumDeltaCharacters > 0),
        assert(maximumTotalCharacters > 0),
        assert(maximumDeltas > 0);

  final int maximumDeltaCharacters;
  final int maximumTotalCharacters;
  final int maximumDeltas;
}

class NeuraTurnDelta {
  const NeuraTurnDelta({
    required this.turnId,
    required this.text,
    required this.isFinal,
  });

  final String turnId;
  final String text;
  final bool isFinal;

  bool get grantsExecutionAuthority => false;
}

/// Coordinates one visible conversational turn at a time.
///
/// It binds model cancellation to Presence Engine barge-in, suppresses stale
/// stream output, rejects control characters and unbounded output, and labels
/// every delta as non-authoritative display text.
class NeuraConversationTurnCoordinator {
  NeuraConversationTurnCoordinator({
    required this.modelRouter,
    required this.presenceEngine,
    this.limits = const NeuraTurnLimits(),
  });

  final NeuraLocalModelRouter modelRouter;
  final NeuraPresenceEngine presenceEngine;
  final NeuraTurnLimits limits;

  static final RegExp _disallowedControlCharacters = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',
  );

  int _nextTurnSequence = 0;
  String? _activeTurnId;
  NeuraCancellationToken? _activeCancellation;

  String? get activeTurnId => _activeTurnId;
  bool get hasActiveTurn => _activeTurnId != null;

  Stream<NeuraTurnDelta> startTurn(NeuraModelRequest request) async* {
    if (presenceEngine.isQuiet) {
      throw StateError('Quiet mode blocks conversational generation.');
    }

    cancelActiveTurn();
    final turnId = 'neura-turn-${_nextTurnSequence++}';
    final cancellation = NeuraCancellationToken();
    _activeTurnId = turnId;
    _activeCancellation = cancellation;
    presenceEngine.beginThinking();

    var totalCharacters = 0;
    var deltaCount = 0;
    var sawFinalDelta = false;

    try {
      await for (final delta in modelRouter.generate(
        request,
        cancellation: cancellation,
      )) {
        if (cancellation.isCancelled || _activeTurnId != turnId) {
          return;
        }

        _validateDelta(delta);
        deltaCount += 1;
        totalCharacters += delta.text.length;
        if (deltaCount > limits.maximumDeltas) {
          throw StateError('Model output exceeded the bounded delta limit.');
        }
        if (totalCharacters > limits.maximumTotalCharacters) {
          throw StateError(
            'Model output exceeded the bounded character limit.',
          );
        }

        if (delta.text.isNotEmpty &&
            presenceEngine.state == NeuraPresenceState.thinking) {
          presenceEngine.beginSpeaking();
        }

        yield NeuraTurnDelta(
          turnId: turnId,
          text: delta.text,
          isFinal: delta.isFinal,
        );

        if (delta.isFinal) {
          sawFinalDelta = true;
          break;
        }
      }

      if (!cancellation.isCancelled &&
          _activeTurnId == turnId &&
          !sawFinalDelta) {
        throw StateError('Model stream ended without a final delta.');
      }
    } on StateError {
      if (!cancellation.isCancelled) {
        rethrow;
      }
    } finally {
      if (_activeTurnId == turnId) {
        _activeTurnId = null;
        _activeCancellation = null;
        if (!presenceEngine.isQuiet &&
            presenceEngine.state != NeuraPresenceState.interrupted) {
          presenceEngine.completeSpeech();
        }
      }
    }
  }

  void cancelActiveTurn() {
    _activeCancellation?.cancel();
    _activeCancellation = null;
    _activeTurnId = null;
  }

  Future<void> interruptForUserSpeech({DateTime? now}) async {
    _activeCancellation?.cancel();
    _activeCancellation = null;
    _activeTurnId = null;
    await presenceEngine.interruptForUserSpeech(now: now);
  }

  Future<void> enterQuietMode({DateTime? now}) async {
    cancelActiveTurn();
    await presenceEngine.enterQuietMode(now: now);
  }

  void leaveQuietMode() {
    presenceEngine.leaveQuietMode();
  }

  void _validateDelta(NeuraModelDelta delta) {
    if (delta.text.length > limits.maximumDeltaCharacters) {
      throw StateError('Model delta exceeded the bounded character limit.');
    }
    if (_disallowedControlCharacters.hasMatch(delta.text)) {
      throw StateError('Model delta contained disallowed control characters.');
    }
  }
}
