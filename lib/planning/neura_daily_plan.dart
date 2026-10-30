import 'package:flutter/foundation.dart';

/// A local checklist, never an action executor or source of model authority.
/// Content stays in RAM and is cleared by its owning screen on background.
class NeuraDailyPlan extends ChangeNotifier {
  String _goal = '';
  List<String> _steps = const [];
  final Set<int> _completed = {};
  bool _approved = false;

  String get goal => _goal;
  List<String> get steps => List.unmodifiable(_steps);
  bool get approved => _approved;
  int get completedCount => _completed.length;
  bool isComplete(int index) => _completed.contains(index);

  void preview(String goal, Iterable<String> steps) {
    final nextGoal = goal.trim();
    final next = steps.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (nextGoal.isEmpty ||
        nextGoal.length > 200 ||
        next.isEmpty ||
        next.length > 8 ||
        next.any((s) => s.length > 160)) {
      throw ArgumentError(
        'Use a goal and 1–8 steps, each up to 160 characters.',
      );
    }
    _goal = nextGoal;
    _steps = List.unmodifiable(next);
    _completed.clear();
    _approved = false;
    notifyListeners();
  }

  void approve() {
    if (_steps.isEmpty) throw StateError('Preview a plan first.');
    _approved = true;
    notifyListeners();
  }

  void complete(int index, bool completed) {
    if (!_approved || index < 0 || index >= _steps.length) {
      throw StateError('Approve the current plan before recording progress.');
    }
    if (completed) {
      _completed.add(index);
    } else {
      _completed.remove(index);
    }
    notifyListeners();
  }

  void clear() {
    _goal = '';
    _steps = const [];
    _completed.clear();
    _approved = false;
    notifyListeners();
  }
}
