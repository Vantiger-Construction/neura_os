import '../reliability/safe_boot.dart';

enum NeuraReflexCommand {
  stop,
  cancel,
  beQuiet,
  stopListening,
  enterSafeMode,
  undo,
  doNotRemember,
  clearConversation,
}

class NeuraReflexResult {
  const NeuraReflexResult({
    required this.recognized,
    this.command,
    this.message = '',
  });

  final bool recognized;
  final NeuraReflexCommand? command;
  final String message;
}

typedef NeuraReflexAction = Future<void> Function();

Future<void> _noOpReflexAction() async {}

class NeuraReflexBindings {
  const NeuraReflexBindings({
    this.cancelGeneration = _noOpReflexAction,
    this.stopSpeech = _noOpReflexAction,
    this.stopListening = _noOpReflexAction,
    this.releaseAudioFocus = _noOpReflexAction,
    this.enterSafeMode = _noOpReflexAction,
    this.undoLastAction = _noOpReflexAction,
    this.forgetCurrentInput = _noOpReflexAction,
    this.clearConversation = _noOpReflexAction,
  });

  factory NeuraReflexBindings.withSafeBoot({
    NeuraReflexAction cancelGeneration = _noOpReflexAction,
    NeuraReflexAction stopSpeech = _noOpReflexAction,
    NeuraReflexAction stopListening = _noOpReflexAction,
    NeuraReflexAction releaseAudioFocus = _noOpReflexAction,
    NeuraReflexAction undoLastAction = _noOpReflexAction,
    NeuraReflexAction forgetCurrentInput = _noOpReflexAction,
    NeuraReflexAction clearConversation = _noOpReflexAction,
  }) {
    return NeuraReflexBindings(
      cancelGeneration: cancelGeneration,
      stopSpeech: stopSpeech,
      stopListening: stopListening,
      releaseAudioFocus: releaseAudioFocus,
      enterSafeMode: SafeBoot.instance.requestSafeMode,
      undoLastAction: undoLastAction,
      forgetCurrentInput: forgetCurrentInput,
      clearConversation: clearConversation,
    );
  }

  final NeuraReflexAction cancelGeneration;
  final NeuraReflexAction stopSpeech;
  final NeuraReflexAction stopListening;
  final NeuraReflexAction releaseAudioFocus;
  final NeuraReflexAction enterSafeMode;
  final NeuraReflexAction undoLastAction;
  final NeuraReflexAction forgetCurrentInput;
  final NeuraReflexAction clearConversation;
}

/// Tiny deterministic command layer that does not consult a model.
class NeuraReflexSafetyLayer {
  NeuraReflexSafetyLayer({
    required this.bindings,
  });

  final NeuraReflexBindings bindings;

  Future<NeuraReflexResult> handle(String input) async {
    final normalized = _normalize(input);
    final command = _commands[normalized];

    if (command == null) {
      return const NeuraReflexResult(
        recognized: false,
        message: 'No deterministic reflex command matched.',
      );
    }

    switch (command) {
      case NeuraReflexCommand.stop:
      case NeuraReflexCommand.cancel:
        await _stopAll();
        break;
      case NeuraReflexCommand.beQuiet:
        await bindings.cancelGeneration();
        await bindings.stopSpeech();
        await bindings.releaseAudioFocus();
        break;
      case NeuraReflexCommand.stopListening:
        await bindings.stopListening();
        await bindings.releaseAudioFocus();
        break;
      case NeuraReflexCommand.enterSafeMode:
        await _stopAll();
        await bindings.enterSafeMode();
        break;
      case NeuraReflexCommand.undo:
        await bindings.undoLastAction();
        break;
      case NeuraReflexCommand.doNotRemember:
        await bindings.forgetCurrentInput();
        break;
      case NeuraReflexCommand.clearConversation:
        await bindings.clearConversation();
        break;
    }

    return NeuraReflexResult(
      recognized: true,
      command: command,
      message: 'Reflex command completed.',
    );
  }

  Future<void> _stopAll() async {
    await bindings.cancelGeneration();
    await bindings.stopSpeech();
    await bindings.stopListening();
    await bindings.releaseAudioFocus();
  }

  static String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9' ]"), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static const Map<String, NeuraReflexCommand> _commands = {
    'stop': NeuraReflexCommand.stop,
    'cancel': NeuraReflexCommand.cancel,
    'be quiet': NeuraReflexCommand.beQuiet,
    'stop listening': NeuraReflexCommand.stopListening,
    'enter safe mode': NeuraReflexCommand.enterSafeMode,
    'safe mode': NeuraReflexCommand.enterSafeMode,
    'undo': NeuraReflexCommand.undo,
    'undo that': NeuraReflexCommand.undo,
    "don't remember this": NeuraReflexCommand.doNotRemember,
    'do not remember this': NeuraReflexCommand.doNotRemember,
    'clear this conversation': NeuraReflexCommand.clearConversation,
  };
}
