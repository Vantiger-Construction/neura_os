import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../avatar/avatar_controller_viseme_ext.dart';
import '../../avatar/avatar_globals.dart';
import '../../avatar/neura_mic_driver.dart';
import '../../core/neura_event_bus.dart';
import '../../core/neura_events.dart';
import '../../services/neura_voice_pack.dart';
import '../models/neura_room.dart';

// Rive avatar is excluded from the beta Windows build (requires ClangCL).
// The widget retains full drag/position/room-transition behaviour and renders
// the static fallback image. Re-add rive when ClangCL is available.
class NeuraRiveResident extends StatefulWidget {
  final NeuraRoom room;
  final double widthFactor;

  const NeuraRiveResident({
    super.key,
    required this.room,
    this.widthFactor = 0.32,
  });

  @override
  State<NeuraRiveResident> createState() => _NeuraRiveResidentState();
}

class _NeuraRiveResidentState extends State<NeuraRiveResident>
    with SingleTickerProviderStateMixin {
  static const _prefsPrefix = 'neura.resident.pos.';

  late final AnimationController _move;
  Offset _posFrac = const Offset(0.82, 0.78);
  Offset _from = const Offset(0.82, 0.78);
  Offset _to = const Offset(0.82, 0.78);

  bool _pinned = false;
  StreamSubscription? _voiceSub;
  Timer? _silenceTimer;
  Timer? _thinkingTimer;

  static const _kSilenceDelay = Duration(milliseconds: 500);
  static const _kThinkingDelay = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    _move = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    _move.addListener(() {
      final t = Curves.easeInOutCubic.transform(_move.value);
      setState(() {
        _posFrac = Offset(
          lerpDouble(_from.dx, _to.dx, t)!,
          lerpDouble(_from.dy, _to.dy, t)!,
        );
      });
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // NeuraVoicePack is initialised in main() before the widget tree builds.
    await _loadPosition();
    _voiceSub?.cancel();
    _voiceSub = NeuraVoicePack.I.stream.listen((f) {
      // Talking state -> event bus so AvatarOrchestrator and other listeners react.
      NeuraEventBus.I.emit(NeuraTalkingEvent(f.talkLevel > 0.05));
      // Mouth-open is per-frame; goes direct to avoid bus overhead.
      AvatarGlobals.controller.setMouthOpen(f.talkLevel);
      // mic_level drives sub-animations in Rive (e.g. glow intensity).
      AvatarGlobals.controller.setNumberInput('mic_level', f.talkLevel);
      // Listening / thinking state machine (idle -> listening -> thinking -> idle).
      if (f.talkLevel > NeuraMicDriver.kListenThreshold) {
        _onVoiceDetected();
      } else {
        _onSilenceDetected();
      }
    });
    if (mounted) setState(() {});
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
    if (!AvatarGlobals.controller.signals.isListening) return;
    _silenceTimer ??= Timer(_kSilenceDelay, () {
      // Voice ended -> thinking state.
      NeuraEventBus.I.emit(const NeuraListeningEvent(false));
      NeuraEventBus.I.emit(const NeuraThinkingEvent(true));
      _thinkingTimer = Timer(_kThinkingDelay, () {
        // Thinking window elapsed -> back to idle (unless TTS started externally).
        if (!AvatarGlobals.controller.signals.isTalking) {
          NeuraEventBus.I.emit(const NeuraThinkingEvent(false));
        }
        _thinkingTimer = null;
      });
      _silenceTimer = null;
    });
  }

  @override
  void didUpdateWidget(covariant NeuraRiveResident oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _onRoomChanged(widget.room);
    }
  }

  Future<void> _onRoomChanged(NeuraRoom room) async {
    if (_pinned) return;
    final anchor = _defaultAnchor(room);
    _from = _posFrac;
    _to = anchor;
    _move.forward(from: 0);
    await _savePosition(anchor, pinned: false);
  }

  Offset _defaultAnchor(NeuraRoom room) {
    switch (room.id) {
      case 'penthouse':
        return const Offset(0.80, 0.78);
      case 'reflection_bay':
        return const Offset(0.74, 0.80);
      case 'joy_lounge':
        return const Offset(0.78, 0.80);
      case 'mood_den':
        return const Offset(0.83, 0.82);
      case 'dream_atrium':
        return const Offset(0.76, 0.78);
      case 'legacy_vault':
        return const Offset(0.86, 0.80);
      default:
        return const Offset(0.80, 0.78);
    }
  }

  Future<void> _loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefsPrefix${widget.room.id}');
    if (raw == null || raw.isEmpty) {
      _posFrac = _defaultAnchor(widget.room);
      _from = _posFrac;
      _to = _posFrac;
      _pinned = false;
      return;
    }
    try {
      final parts = raw.split(',');
      final dx = double.parse(parts[0]);
      final dy = double.parse(parts[1]);
      final pin = (parts.length >= 3) ? (parts[2] == '1') : false;
      _posFrac = Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0));
      _from = _posFrac;
      _to = _posFrac;
      _pinned = pin;
    } catch (_) {
      _posFrac = _defaultAnchor(widget.room);
      _pinned = false;
    }
  }

  Future<void> _savePosition(Offset frac, {required bool pinned}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefsPrefix${widget.room.id}',
      '${frac.dx.toStringAsFixed(6)},${frac.dy.toStringAsFixed(6)},${pinned ? 1 : 0}',
    );
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _thinkingTimer?.cancel();
    _voiceSub?.cancel();
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final neuraW = (w * widget.widthFactor).clamp(180.0, 420.0);
        final neuraH = neuraW * 2.05;
        final left = (w * _posFrac.dx) - neuraW / 2;
        final top = (h * _posFrac.dy) - neuraH;
        final maxLeft = w > neuraW ? w - neuraW : 0.0;
        final maxTop = h > neuraH ? h - neuraH : 0.0;

        return Stack(
          children: [
            Positioned(
              left: left.clamp(0.0, maxLeft),
              top: top.clamp(0.0, maxTop),
              width: neuraW,
              height: neuraH,
              child: GestureDetector(
                onPanStart: (_) => _pinned = true,
                onPanUpdate: (d) {
                  final next = Offset(
                    (_posFrac.dx + d.delta.dx / w).clamp(0.05, 0.95),
                    (_posFrac.dy + d.delta.dy / h).clamp(0.35, 0.95),
                  );
                  setState(() => _posFrac = next);
                },
                onPanEnd: (_) async {
                  await _savePosition(_posFrac, pinned: true);
                },
                onDoubleTap: () {
                  _pinned = false;
                  final anchor = _defaultAnchor(widget.room);
                  _from = _posFrac;
                  _to = anchor;
                  _move.forward(from: 0);
                  _savePosition(anchor, pinned: false);
                },
                child: Opacity(
                  opacity: 0.95,
                  child: _fallbackImage(context),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _fallbackImage(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/neura_fullbody.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Center(
              child: Text(
                'NEURA',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    blurRadius: 40,
                    spreadRadius: 6,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
