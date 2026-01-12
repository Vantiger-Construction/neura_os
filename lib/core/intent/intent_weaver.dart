import 'dart:async';
import 'intent_vector.dart';

class IntentWeave {
  final NeuraIntent intent;
  final DateTime startedAt;
  bool completed = false;
  IntentWeave(this.intent) : startedAt = DateTime.now();
}

class IntentWeaver {
  final Duration stabilityThreshold;
  final Duration cooldown;
  IntentWeave? _active;
  DateTime _lastCompleted = DateTime.fromMillisecondsSinceEpoch(0);

  final _weaveStream = StreamController<IntentWeave>.broadcast();
  Stream<IntentWeave> get weaves => _weaveStream.stream;

  IntentWeaver({this.stabilityThreshold = const Duration(seconds: 30), this.cooldown = const Duration(minutes: 5)});

  void onIntent(IntentVector vector) {
    final top = vector.topIntent;
    final now = DateTime.now();
    if (now.difference(_lastCompleted) < cooldown) return;

    if (_active == null || _active!.intent != top) {
      _active = IntentWeave(top);
      return;
    }

    if (!_active!.completed && now.difference(_active!.startedAt) >= stabilityThreshold) {
      _active!.completed = true;
      _lastCompleted = now;
      _weaveStream.add(_active!);
    }
  }

  void dispose() {
    _weaveStream.close();
  }
}
