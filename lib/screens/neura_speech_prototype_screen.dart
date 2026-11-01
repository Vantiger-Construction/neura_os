import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../avatar/avatar_controller.dart';
import '../avatar/avatar_globals.dart';
import '../avatar/renderers/flutter_mouth_avatar_view.dart';
import '../reliability/safe_boot.dart';
import '../services/neura_tts_service.dart';

/// Explicit, local-only preview for the synthetic mouth-compatible artwork.
/// Opening this route never starts speech, capture or a model request.
class NeuraSpeechPrototypeScreen extends StatefulWidget {
  const NeuraSpeechPrototypeScreen({super.key, this.controller, this.speech});

  final AvatarController? controller;
  final NeuraTtsService? speech;

  @override
  State<NeuraSpeechPrototypeScreen> createState() =>
      _NeuraSpeechPrototypeScreenState();
}

class _NeuraSpeechPrototypeScreenState
    extends State<NeuraSpeechPrototypeScreen> {
  late final NeuraTtsService _speech =
      widget.speech ?? NeuraTtsService.instance;
  // Borrowed services let the native-channel fixture run on a hosted OS.
  // Production playback is restricted to Windows' owned local SAPI adapter.
  bool get _supported =>
      widget.speech != null ||
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows);
  bool _speaking = false;
  bool _usedSpeech = false;
  String? _error;
  int _request = 0;

  Future<void> _speak() async {
    if (!_supported || SafeBoot.instance.safeMode.value) return;
    final request = ++_request;
    _usedSpeech = true;
    setState(() {
      _speaking = true;
      _error = null;
    });
    try {
      await _speech.speak('Mama, Papa, baby. We owe you a blue balloon.');
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = 'Local speech is unavailable.');
      }
    } finally {
      if (mounted && request == _request) setState(() => _speaking = false);
    }
  }

  void _stop() {
    final request = ++_request;
    setState(() => _speaking = false);
    unawaited(_speech.stop().catchError((Object _) {
      if (mounted && request == _request) {
        setState(() => _error = 'Local speech is unavailable.');
      }
    }));
  }

  @override
  void dispose() {
    ++_request;
    if (_usedSpeech) unawaited(_speech.stop().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Neura speech prototype')),
        body: Center(
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FlutterMouthAvatarView(
                controller: widget.controller ?? AvatarGlobals.controller,
                size: 240),
            const SizedBox(height: 24),
            const Text('A local voice preview with a simple expressive face.',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ValueListenableBuilder<bool>(
                valueListenable: SafeBoot.instance.safeMode,
                builder: (context, safe, _) => FilledButton.icon(
                      onPressed: safe || !_supported ? null : _speak,
                      icon: const Icon(Icons.volume_up),
                      label: Text(!_supported
                          ? 'Available on Windows'
                          : safe
                              ? 'Speech off in Safe Mode'
                              : _speaking
                                  ? 'Speak again'
                                  : 'Play local sample'),
                    )),
            TextButton(
                onPressed: _speaking ? _stop : null, child: const Text('Stop')),
            if (_error != null) Text(_error!, textAlign: TextAlign.center),
          ]),
        )),
      );
}
