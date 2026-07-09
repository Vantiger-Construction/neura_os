import 'dart:async';

import 'package:flutter/material.dart';

/// Guided 4-7-8 breathing exercise for kids.
///
/// Each cycle: Inhale 4 s → Hold 7 s → Exhale 8 s.
/// A circle animates in/out to show what to do.
class BreathingGameScreen extends StatefulWidget {
  const BreathingGameScreen({super.key});

  @override
  State<BreathingGameScreen> createState() => _BreathingGameScreenState();
}

enum _Phase { ready, inhale, hold, exhale }

class _BreathingGameScreenState extends State<BreathingGameScreen>
    with SingleTickerProviderStateMixin {
  static const int _inhaleSec = 4;
  static const int _holdSec = 7;
  static const int _exhaleSec = 8;

  _Phase _phase = _Phase.ready;
  int _secondsLeft = 0;
  int _cyclesComplete = 0;
  Timer? _timer;

  late AnimationController _animController;
  late Animation<double> _sizeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _inhaleSec),
    );
    _sizeAnim = Tween<double>(begin: 120, end: 220).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _startCycle() {
    _enterPhase(_Phase.inhale);
  }

  void _enterPhase(_Phase phase) {
    _timer?.cancel();
    int duration;
    switch (phase) {
      case _Phase.inhale:
        duration = _inhaleSec;
        _animController.duration = const Duration(seconds: _inhaleSec);
        _animController.forward(from: 0);
      case _Phase.hold:
        duration = _holdSec;
        _animController.value = 1.0;
      case _Phase.exhale:
        duration = _exhaleSec;
        _animController.duration = const Duration(seconds: _exhaleSec);
        _animController.reverse(from: 1);
      case _Phase.ready:
        duration = 0;
    }

    setState(() {
      _phase = phase;
      _secondsLeft = duration;
    });

    if (phase == _Phase.ready) return;

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final remaining = _secondsLeft - 1;
      if (remaining <= 0) {
        t.cancel();
        _nextPhase();
      } else {
        setState(() => _secondsLeft = remaining);
      }
    });
  }

  void _nextPhase() {
    switch (_phase) {
      case _Phase.inhale:
        _enterPhase(_Phase.hold);
      case _Phase.hold:
        _enterPhase(_Phase.exhale);
      case _Phase.exhale:
        setState(() => _cyclesComplete++);
        _enterPhase(_Phase.inhale);
      case _Phase.ready:
        break;
    }
  }

  void _stop() {
    _timer?.cancel();
    _animController.stop();
    setState(() {
      _phase = _Phase.ready;
      _secondsLeft = 0;
    });
  }

  String get _phaseLabel {
    switch (_phase) {
      case _Phase.ready:
        return 'Ready when you are';
      case _Phase.inhale:
        return 'Breathe IN';
      case _Phase.hold:
        return 'Hold';
      case _Phase.exhale:
        return 'Breathe OUT';
    }
  }

  Color get _phaseColor {
    switch (_phase) {
      case _Phase.ready:
        return Colors.deepPurple.shade200;
      case _Phase.inhale:
        return Colors.lightBlue.shade300;
      case _Phase.hold:
        return Colors.amber.shade300;
      case _Phase.exhale:
        return Colors.teal.shade300;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calm Breathing'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _sizeAnim,
                builder: (_, __) {
                  return Container(
                    width: _sizeAnim.value,
                    height: _sizeAnim.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _phaseColor.withValues(alpha:0.25),
                      border: Border.all(color: _phaseColor, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: _phaseColor.withValues(alpha:0.4),
                          blurRadius: 30,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                    child: Center(
                      child: _phase != _Phase.ready
                          ? Text(
                              '$_secondsLeft',
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                color: _phaseColor,
                              ),
                            )
                          : Icon(Icons.air, size: 48, color: _phaseColor),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              Text(
                _phaseLabel,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: _phaseColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Inhale 4 • Hold 7 • Exhale 8',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha:0.5),
                ),
              ),
              const SizedBox(height: 40),
              if (_cyclesComplete > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    '${_cyclesComplete == 1 ? '1 cycle' : '$_cyclesComplete cycles'} complete 🌟',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              _phase == _Phase.ready
                  ? ElevatedButton.icon(
                      onPressed: _startCycle,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Breathing'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple.shade400,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 14),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: _stop,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: const BorderSide(color: Colors.white24),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

