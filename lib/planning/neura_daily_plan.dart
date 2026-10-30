import 'package:flutter/foundation.dart';

/// A local checklist, never an action executor or source of model authority.
/// Content stays in RAM and is cleared by its owning screen on background.
class NeuraDailyPlan extends ChangeNotifier {
  String _goal = '';
  List<String> _steps = const [];
  final Set<int> _completed = {};
  bool _approved = false;
  bool _paused = false;

  String get goal => _goal;
  List<String> get steps => List.unmodifiable(_steps);
  bool get approved => _approved;
  int get completedCount => _completed.length;
  bool isComplete(int index) => _completed.contains(index);
  bool get paused => _paused;
  int? get nextStepIndex {
    for (var i = 0; i < _steps.length; i++) {
      if (!_completed.contains(i)) return i;
    }
    return null;
  }

  void pause(bool value) {
    if (!_approved) throw StateError('Approve the plan first.');
    _paused = value;
    notifyListeners();
  }

  void makeCurrentStepSmaller(String replacement) {
    final index = nextStepIndex;
    final text = replacement.trim();
    if (!_approved || index == null || text.isEmpty || text.length > 160) {
      throw ArgumentError('Choose a smaller step up to 160 characters.');
    }
    _steps = List.of(_steps)..[index] = text;
    _approved = false;
    _paused = false;
    notifyListeners();
  }

  /// An imported snapshot is always a preview, never a restored approval.
  void previewTransferred(String goal, List<String> steps, Set<int> completed) {
    if (completed.any((i) => i < 0 || i >= steps.length)) {
      throw ArgumentError('Invalid progress.');
    }
    preview(goal, steps);
    _completed.addAll(completed);
    notifyListeners();
  }

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
    _paused = false;
    notifyListeners();
  }

  void approve() {
    if (_steps.isEmpty) throw StateError('Preview a plan first.');
    _approved = true;
    notifyListeners();
  }

  void complete(int index, bool completed) {
    if (!_approved || _paused || index < 0 || index >= _steps.length) {
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
    _paused = false;
    notifyListeners();
  }
}
