
export 'memory/memory.dart';
export 'emotion/emotion.dart';
export 'behavior/behavior.dart';

import 'memory/memory.dart';
import 'emotion/emotion.dart';
import 'behavior/behavior.dart';

class NeuraSystem {
  late final MemoryCore memory;
  late final EmotionCore emotion;
  late final BehaviorEngine behavior;

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    memory = MemoryCore();
    await memory.init();
    emotion = EmotionCore(memoryCore: memory);
    await emotion.init();
    behavior = BehaviorEngine(memoryCore: memory, emotionCore: emotion);
    await behavior.init();
    _ready = true;
  }
}
