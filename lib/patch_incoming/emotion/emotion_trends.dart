import 'emotion_state.dart';

/// Analyzes emotional trends over time
class EmotionTrends {
  /// Calculate average mood over a list of emotion states
  double calculateAverageMood(List<EmotionState> states) {
    if (states.isEmpty) return 0.5;
    
    final sum = states.fold<double>(0.0, (sum, state) => sum + state.mood);
    return sum / states.length;
  }
  
  /// Calculate average energy over a list of emotion states
  double calculateAverageEnergy(List<EmotionState> states) {
    if (states.isEmpty) return 0.5;
    
    final sum = states.fold<double>(0.0, (sum, state) => sum + state.energy);
    return sum / states.length;
  }
  
  /// Detect if mood is trending upward
  bool isMoodImproving(List<EmotionState> states) {
    if (states.length < 2) return false;
    
    final recent = states.sublist(states.length ~/ 2);
    final earlier = states.sublist(0, states.length ~/ 2);
    
    return calculateAverageMood(recent) > calculateAverageMood(earlier);
  }
}
