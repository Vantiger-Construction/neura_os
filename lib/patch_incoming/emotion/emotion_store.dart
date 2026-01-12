import 'emotion_state.dart';

/// Stores emotion history and state
class EmotionStore {
  final List<EmotionState> _history = [];
  EmotionState _currentState = EmotionState.neutral();
  
  EmotionState get currentState => _currentState;
  
  void updateState(EmotionState newState) {
    _currentState = newState;
    _history.add(newState);
    
    // Keep only recent history (last 100 entries)
    if (_history.length > 100) {
      _history.removeAt(0);
    }
  }
  
  List<EmotionState> getHistory({int limit = 10}) {
    final start = _history.length > limit ? _history.length - limit : 0;
    return _history.sublist(start);
  }
  
  void clear() {
    _history.clear();
    _currentState = EmotionState.neutral();
  }
}
