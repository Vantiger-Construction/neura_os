enum NeuraPresenceState {
  idle,
  listening,
  thinking,
  speaking,
  interrupted,
  quiet,
}

enum NeuraPresenceStyle {
  concise,
  reading,
  coaching,
  comforting,
  quiet,
}

typedef NeuraPresenceAction = Future<void> Function();

Future<void> _noOpPresenceAction() async {}

class NeuraPresenceBindings {
  const NeuraPresenceBindings({
    this.cancelGeneration = _noOpPresenceAction,
    this.stopSpeech = _noOpPresenceAction,
    this.releaseAudioFocus = _noOpPresenceAction,
  });

  final NeuraPresenceAction cancelGeneration;
  final NeuraPresenceAction stopSpeech;
  final NeuraPresenceAction releaseAudioFocus;
}

/// Deterministic presence state machine for speech, barge-in, and mic safety.
class NeuraPresenceEngine {
  NeuraPresenceEngine({
    required this.bindings,
    this.echoGuardDuration = const Duration(milliseconds: 450),
  });

  final NeuraPresenceBindings bindings;
  final Duration echoGuardDuration;

  NeuraPresenceState _state = NeuraPresenceState.idle;
  NeuraPresenceStyle _style = NeuraPresenceStyle.concise;
  DateTime? _speechStoppedAt;

  NeuraPresenceState get state => _state;
  NeuraPresenceStyle get style => _style;
  bool get isSpeaking => _state == NeuraPresenceState.speaking;
  bool get isQuiet => _state == NeuraPresenceState.quiet;

  String? get interruptionAcknowledgement {
    if (_state != NeuraPresenceState.interrupted) {
      return null;
    }
    return 'I stopped. Go ahead.';
  }

  void setStyle(NeuraPresenceStyle style) {
    _style = style;
    if (style == NeuraPresenceStyle.quiet) {
      _state = NeuraPresenceState.quiet;
    } else if (_state == NeuraPresenceState.quiet) {
      _state = NeuraPresenceState.idle;
    }
  }

  void beginListening() {
    if (_state != NeuraPresenceState.quiet) {
      _state = NeuraPresenceState.listening;
    }
  }

  void beginThinking() {
    if (_state != NeuraPresenceState.quiet) {
      _state = NeuraPresenceState.thinking;
    }
  }

  void beginSpeaking() {
    if (_state != NeuraPresenceState.quiet) {
      _state = NeuraPresenceState.speaking;
    }
  }

  void completeSpeech({DateTime? now}) {
    _speechStoppedAt = now ?? DateTime.now().toUtc();
    _state = _style == NeuraPresenceStyle.quiet
        ? NeuraPresenceState.quiet
        : NeuraPresenceState.idle;
  }

  Future<void> interruptForUserSpeech({DateTime? now}) async {
    if (_state != NeuraPresenceState.speaking &&
        _state != NeuraPresenceState.thinking) {
      return;
    }

    await bindings.cancelGeneration();
    await bindings.stopSpeech();
    await bindings.releaseAudioFocus();

    _speechStoppedAt = now ?? DateTime.now().toUtc();
    _state = NeuraPresenceState.interrupted;
  }

  bool canOpenMicrophone({DateTime? now}) {
    if (_state == NeuraPresenceState.speaking ||
        _state == NeuraPresenceState.thinking ||
        _state == NeuraPresenceState.quiet) {
      return false;
    }

    final stoppedAt = _speechStoppedAt;
    if (stoppedAt == null) {
      return true;
    }

    final current = now ?? DateTime.now().toUtc();
    return current.difference(stoppedAt) >= echoGuardDuration;
  }

  Future<void> enterQuietMode({DateTime? now}) async {
    await bindings.cancelGeneration();
    await bindings.stopSpeech();
    await bindings.releaseAudioFocus();
    _speechStoppedAt = now ?? DateTime.now().toUtc();
    _style = NeuraPresenceStyle.quiet;
    _state = NeuraPresenceState.quiet;
  }

  void leaveQuietMode() {
    _style = NeuraPresenceStyle.concise;
    _state = NeuraPresenceState.idle;
  }
}
