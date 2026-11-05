import 'package:flutter/foundation.dart';

/// A local checklist, never an action executor or source of model authority.
/// Content stays in RAM and is cleared by its owning screen on background.
class NeuraDailyPlan extends ChangeNotifier {
  String _goal = '';
  List<String> _steps = const [];
  final Set<int> _completed = {};
  bool _approved = false;
  bool _paused = false;
  ({List<String> steps, Set<int> completed})? _undo;

  String get goal => _goal;
  List<String> get steps => List.unmodifiable(_steps);
  bool get approved => _approved;
  int get completedCount => _completed.length;
  bool isComplete(int index) => _completed.contains(index);
  bool get paused => _paused;
  bool get canUndo => _undo != null;

  static bool _validStep(String text) =>
      text.trim().isNotEmpty &&
      text.trim().length <= 160 &&
      !text.contains(RegExp(r'[\x00-\x1f\x7f]'));

  void _rememberEdit() {
    _undo = (steps: List.of(_steps), completed: Set.of(_completed));
    _approved = false;
    _paused = false;
  }

  void editStep(int index, String replacement) {
    if (index < 0 || index >= _steps.length || !_validStep(replacement)) {
      throw ArgumentError('Choose a step up to 160 characters.');
    }
    final text = replacement.trim();
    if (_steps[index] == text) return;
    _rememberEdit();
    _steps = List.of(_steps)..[index] = text;
    // An edited completed step is new work; other progress stays intact.
    _completed.remove(index);
    notifyListeners();
  }

  void addStep(String text) {
    if (_steps.isEmpty || _steps.length >= 8 || !_validStep(text)) {
      throw ArgumentError('Keep between one and eight steps.');
    }
    _rememberEdit();
    _steps = [..._steps, text.trim()];
    notifyListeners();
  }

  void removeStep(int index) {
    if (_steps.length <= 1 || index < 0 || index >= _steps.length) {
      throw ArgumentError('Keep at least one step.');
    }
    _rememberEdit();
    _steps = List.of(_steps)..removeAt(index);
    final progress = {
      for (final i in _completed)
        if (i != index) i > index ? i - 1 : i
    };
    _completed
      ..clear()
      ..addAll(progress);
    notifyListeners();
  }

  /// [to] is the final index, after moving the step.
  void moveStep(int from, int to) {
    if (from < 0 || to < 0 || from >= _steps.length || to >= _steps.length) {
      throw ArgumentError('Choose an existing step.');
    }
    if (from == to) return;
    _rememberEdit();
    final order = List.generate(_steps.length, (i) => i);
    order.insert(to, order.removeAt(from));
    final progress = {
      for (var i = 0; i < order.length; i++)
        if (_completed.contains(order[i])) i
    };
    _steps = [for (final index in order) _steps[index]];
    _completed
      ..clear()
      ..addAll(progress);
    notifyListeners();
  }

  /// Undo restores one edit, never a prior approval or a cleared session.
  void undoEdit() {
    final previous = _undo;
    if (previous == null) return;
    _steps = previous.steps;
    _completed
      ..clear()
      ..addAll(previous.completed);
    _undo = null;
    _approved = false;
    _paused = false;
    notifyListeners();
  }

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
    if (!_approved || index == null || !_validStep(text)) {
      throw ArgumentError('Choose a smaller step up to 160 characters.');
    }
    editStep(index, text);
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
        nextGoal.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        next.isEmpty ||
        next.length > 8 ||
        next.any((s) => !_validStep(s))) {
      throw ArgumentError(
        'Use a goal and 1–8 steps, each up to 160 characters.',
      );
    }
    _goal = nextGoal;
    _steps = List.unmodifiable(next);
    _completed.clear();
    _approved = false;
    _paused = false;
    _undo = null;
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
    _undo = null;
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
    _undo = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _goal = '';
    _steps = const [];
    _completed.clear();
    _undo = null;
    super.dispose();
  }
}
