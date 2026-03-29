import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:rive/rive.dart' hide Image;
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/neura_voice_pack.dart';
import '../models/neura_room.dart';

/// Full-body Neura, persistent across the OS.
///
/// - Anchors per room (Neura "belongs" somewhere in each penthouse room)
/// - Drag to reposition (per-room)
/// - Double-tap to snap back to room anchor
/// - Drives mouth/talk + visemes from [NeuraVoicePack]
/// - Optional walking flag while transitioning
class NeuraRiveResident extends StatefulWidget {
  final NeuraRoom room;

  /// Visual size of Neura relative to screen width.
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
  bool _riveAvailable = false;

  // Rive
  SMIInput<bool>? _isWalking;
  SMIInput<double>? _talkLevel;
  SMIInput<double>? _rest;
  SMIInput<double>? _aa;
  SMIInput<double>? _ee;
  SMIInput<double>? _oo;
  SMIInput<double>? _ff;
  SMIInput<double>? _mm;

  StreamSubscription? _voiceSub;

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
    // Determine if Neura.riv exists
    try {
      await rootBundle.load('assets/rive/Neura.riv');
      _riveAvailable = true;
    } catch (_) {
      _riveAvailable = false;
    }

    // Start voice pack (safe to call multiple times)
    try {
      await NeuraVoicePack.I.init(enableMic: true);
    } catch (_) {
      // If mic permissions are missing, voice still works for clips.
    }

    await _loadPosition();

    // Subscribe to voice stream and drive Rive inputs.
    _voiceSub?.cancel();
    _voiceSub = NeuraVoicePack.I.stream.listen(_applyVoiceFrame);

    if (mounted) setState(() {});
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

    // Walk flag during transition
    _isWalking?.value = true;
    _move.forward(from: 0).whenComplete(() {
      _isWalking?.value = false;
    });

    await _savePosition(anchor, pinned: false);
  }

  Offset _defaultAnchor(NeuraRoom room) {
    // Screen fractions (0..1). Tune per room.
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

  void _applyVoiceFrame(NeuraVoiceFrame f) {
    // Map voice → Rive (if available)
    _talkLevel?.value = f.talkLevel;
    _rest?.value = f.rest;
    _aa?.value = f.aa;
    _ee?.value = f.ee;
    _oo?.value = f.oo;
    _ff?.value = f.ff;
    _mm?.value = f.mm;
  }

  void _onRiveInit(Artboard artboard) {
    // If your state machine name differs, change here.
    final sm = StateMachineController.fromArtboard(artboard, 'NeuraBrain');
    if (sm == null) return;

    artboard.addController(sm);

    // Input names (update to match your .riv).
    SMIInput<T>? input<T>(String name) => sm.findInput<T>(name);

    _isWalking = input<bool>('isWalking');
    _talkLevel = input<double>('talkLevel');

    _rest = input<double>('rest');
    _aa = input<double>('aa');
    _ee = input<double>('ee');
    _oo = input<double>('oo');
    _ff = input<double>('ff');
    _mm = input<double>('mm');

    // Start idle
    _isWalking?.value = false;
    _applyVoiceFrame(NeuraVoiceFrame.idle);
  }

  @override
  void dispose() {
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

        // Position is expressed as a fraction of the screen.
        final left = (w * _posFrac.dx) - neuraW / 2;
        final top = (h * _posFrac.dy) - neuraH;

        return Positioned(
          left: left.clamp(0.0, w - neuraW),
          top: top.clamp(0.0, h - neuraH),
          width: neuraW,
          height: neuraH,
          child: GestureDetector(
            onPanStart: (_) {
              _pinned = true;
              _isWalking?.value = true;
            },
            onPanUpdate: (d) {
              // Convert pixel delta to fraction delta
              final dx = d.delta.dx / w;
              final dy = d.delta.dy / h;
              final next = Offset(
                (_posFrac.dx + dx).clamp(0.05, 0.95),
                (_posFrac.dy + dy).clamp(0.35, 0.95),
              );
              setState(() => _posFrac = next);
            },
            onPanEnd: (_) async {
              _isWalking?.value = false;
              await _savePosition(_posFrac, pinned: true);
            },
            onDoubleTap: () {
              // Snap back to anchor for this room.
              _pinned = false;
              final anchor = _defaultAnchor(widget.room);
              _from = _posFrac;
              _to = anchor;
              _isWalking?.value = true;
              _move.forward(from: 0).whenComplete(() {
                _isWalking?.value = false;
              });
              _savePosition(anchor, pinned: false);
            },
            child: IgnorePointer(
              ignoring: false,
              child: Opacity(
                opacity: 0.95,
                child: _riveAvailable
                    ? RiveAnimation.asset(
                        'assets/rive/Neura.riv',
                        fit: BoxFit.contain,
                        onInit: _onRiveInit,
                      )
                    : _fallbackImage(context),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fallbackImage(BuildContext context) {
    // If the Rive asset isn't present, we keep the OS running.
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/ai_avatar.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) {
              return Center(
                child: Text(
                  'NEURA',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              );
            },
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
        )
      ],
    );
  }
}
