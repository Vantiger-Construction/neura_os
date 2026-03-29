import '../memory/memory_core.dart';
import 'emotion_state.dart';
import 'emotion_store.dart';
import 'emotion_analyzer.dart';

/// Central emotion system: tracks, stores, and exposes the latest emotional state.
class EmotionCore {
  final MemoryCore memoryCore;
  final EmotionStore _store = EmotionStore();
  final EmotionAnalyzer _analyzer = EmotionAnalyzer();

  List<EmotionState> _history = [];

  EmotionCore({required this.memoryCore});

  EmotionState? get latest => _history.isEmpty ? null : _history.last;

  Future<void> init() async {
    _history = await _store.load();
  }

  Future<void> recordFromText(String text) async {
    final state = _analyzer.analyze(text);
    _history.add(state);
    await _store.append(state);
  }

  Future<void> recordState(EmotionState state) async {
    _history.add(state);
    await _store.append(state);
  }

  List<EmotionState> get history => List.unmodifiable(_history);
}
