import 'package:flutter/foundation.dart';

import 'neura_chat_policy.dart';

/// Small shared runtime channel for model-requested presentation tone.
///
/// Avatar/motor surfaces can listen to [tone] without coupling the LLM client
/// to a particular renderer. Invalid values are ignored even if a future
/// caller bypasses the model-tool validation layer.
class NeuraToneRuntime {
  NeuraToneRuntime._();
  static final NeuraToneRuntime instance = NeuraToneRuntime._();

  final ValueNotifier<String> tone = ValueNotifier<String>('warm_companion');

  bool setTone(String value) {
    if (!NeuraChatPolicy.knownTones.contains(value)) return false;
    if (tone.value != value) tone.value = value;
    return true;
  }
}
