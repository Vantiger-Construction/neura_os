// lib/avatar/neura_presence_view.dart
//
// Drop-in widget that shows the avatar and drives it in real time from the
// microphone.  Listening/thinking/idle state transitions are emitted onto
// NeuraEventBus so the AvatarOrchestrator (and any other listener) can react;
// only the per-frame mic_level number input goes directly to the controller.
//
//   mic.attachLevel((lvl) => controller.setNumberInput('mic_level', lvl));
//   NeuraEventBus.I.emit(NeuraListeningEvent(true/false));
//   // State sequence: idle → listening → thinking → speaking → idle
//
// Usage — embed anywhere, e.g. the home screen or a conversation screen:
//
//   NeuraPresenceView(size: 200)
//
// The widget manages its own mic lifecycle.  TTS-playback state (speaking) must
// be driven externally via AvatarGlobals.controller.setTalking(true/false).

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/neura_event_bus.dart';
import '../core/neura_events.dart';
import '../services/avatar_service.dart';
import 'avatar_controller.dart';
import 'avatar_globals.dart';
import 'avatar_registry.dart';
import 'avatar_view.dart';
import 'neura_mic_driver.dart';

/// Full-presence avatar widget: shows the avatar and animates it from the mic.
class NeuraPresenceView extends StatefulWidget {
  final double size;

  /// Override to supply a non-global controller (useful for isolated screens).
  final AvatarController? controller;

  /// Override to supply a non-global avatar service.
  final AvatarService? avatarService;

  const NeuraPresenceView({
    super.key,
    this.size = 200,
    this.controller,
    this.avatarService,
  });

  @override
  State<NeuraPresenceView> createState() => _NeuraPresenceViewState();
}

class _NeuraPresenceViewState extends State<NeuraPresenceView> {
  // _controller is kept for the per-frame mic_level number input only.
  // Listening/thinking state transitions go through NeuraEventBus so the
  // AvatarOrchestrator (and any other listener) can react to them.
  late final AvatarController _controller;
  late final AvatarService _service;

  final NeuraMicDriver _mic = NeuraMicDriver();
  StreamSubscription<double>? _levelSub;

  // Debounce timers for the listening → thinking → idle state machine.
  Timer? _silenceTimer;
  Timer? _thinkingTimer;

  static const _kSilenceDelay = Duration(milliseconds: 500);
  static const _kThinkingDelay = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? AvatarGlobals.controller;
    _service = widget.avatarService ?? AvatarGlobals.service;
    _startMic();
  }

  Future<void> _startMic() async {
    final started = await _mic.start();
    if (!started || !mounted) return;

    // ── Mic wiring ────────────────────────────────────────────────────────────
    // 1. Forward raw amplitude directly to the controller's number input
    //    (per-frame; drives sub-animations in Rive when supported).
    // 2. State transitions (listening / thinking) go through NeuraEventBus so
    //    AvatarOrchestrator and any other listener can react.
    // ─────────────────────────────────────────────────────────────────────────
    _levelSub = _mic.attachLevel((lvl) {
      _controller.setNumberInput('mic_level', lvl); // direct – per frame
      if (lvl > NeuraMicDriver.kListenThreshold) {
        _onVoiceDetected();
      } else {
        _onSilenceDetected();
      }
    });
  }

  void _onVoiceDetected() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _thinkingTimer?.cancel();
    _thinkingTimer = null;
    NeuraEventBus.I.emit(const NeuraListeningEvent(true));
    NeuraEventBus.I.emit(const NeuraThinkingEvent(false));
  }

  void _onSilenceDetected() {
    if (!_controller.signals.isListening) return; // already idle, nothing to do
    _silenceTimer ??= Timer(_kSilenceDelay, () {
      // Voice ended → thinking state
      NeuraEventBus.I.emit(const NeuraListeningEvent(false));
      NeuraEventBus.I.emit(const NeuraThinkingEvent(true));

      _thinkingTimer = Timer(_kThinkingDelay, () {
        // Thinking window elapsed → back to idle (unless TTS started externally)
        if (!_controller.signals.isTalking) {
          NeuraEventBus.I.emit(const NeuraThinkingEvent(false));
        }
        _thinkingTimer = null;
      });
      _silenceTimer = null;
    });
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _thinkingTimer?.cancel();
    _levelSub?.cancel();
    _mic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _service.selectedAvatarId,
      builder: (_, id, __) {
        final spec = AvatarRegistry.byId(id);
        return AvatarView(
          spec: spec,
          controller: _controller,
          size: widget.size,
        );
      },
    );
  }
}
