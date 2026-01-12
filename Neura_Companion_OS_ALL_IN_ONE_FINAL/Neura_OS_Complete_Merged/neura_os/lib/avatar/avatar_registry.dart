import 'avatar_asset.dart';
import 'avatar_types.dart';

/// Central place to define which avatars exist and how they render.
///
/// Swap assets freely without changing code elsewhere.
class AvatarRegistry {
  static const String defaultAvatarId = 'neura';

  static final List<AvatarSpec> _avatars = [
    AvatarSpec(
      id: 'neura',
      name: 'Neura',
      format: AvatarFormat.rive,
      assetPath: 'assets/rive/neura.riv',
      fallbackAssetPath: 'assets/animations/neura_idle.json',
      rive: AvatarRiveConfig(
        // Use your own artboard/state machine names as needed.
        artboard: null,
        stateMachine: 'NeuraState',
        inputNames: {
          // Canonical -> actual (default assumes canonical names match the file).
          AvatarRiveInputs.isListening: AvatarRiveInputs.isListening,
          AvatarRiveInputs.isTalking: AvatarRiveInputs.isTalking,
          AvatarRiveInputs.isThinking: AvatarRiveInputs.isThinking,
          AvatarRiveInputs.isError: AvatarRiveInputs.isError,
          AvatarRiveInputs.mood: AvatarRiveInputs.mood,
          AvatarRiveInputs.energy: AvatarRiveInputs.energy,
          AvatarRiveInputs.wave: AvatarRiveInputs.wave,
          AvatarRiveInputs.blink: AvatarRiveInputs.blink,
        },
      ),
      lottie: const AvatarLottieConfig(variants: {
        'idle': 'assets/animations/neura_idle.json',
        'talk': 'assets/animations/neura_talk.json',
        'listen': 'assets/animations/neura_listen.json',
        'think': 'assets/animations/neura_think.json',
        'error': 'assets/animations/neura_error.json',
      }),
    ),
    AvatarSpec(
      id: 'neuro',
      name: 'Neuro',
      format: AvatarFormat.rive,
      assetPath: 'assets/rive/neuro.riv',
      fallbackAssetPath: 'assets/animations/neuro_idle.json',
      rive: AvatarRiveConfig(
        artboard: null,
        stateMachine: 'NeuroState',
        inputNames: {
          AvatarRiveInputs.isListening: AvatarRiveInputs.isListening,
          AvatarRiveInputs.isTalking: AvatarRiveInputs.isTalking,
          AvatarRiveInputs.isThinking: AvatarRiveInputs.isThinking,
          AvatarRiveInputs.isError: AvatarRiveInputs.isError,
          AvatarRiveInputs.mood: AvatarRiveInputs.mood,
          AvatarRiveInputs.energy: AvatarRiveInputs.energy,
          AvatarRiveInputs.wave: AvatarRiveInputs.wave,
          AvatarRiveInputs.blink: AvatarRiveInputs.blink,
        },
      ),
      lottie: const AvatarLottieConfig(variants: {
        'idle': 'assets/animations/neuro_idle.json',
        'talk': 'assets/animations/neuro_talk.json',
        'listen': 'assets/animations/neuro_listen.json',
        'think': 'assets/animations/neuro_think.json',
        'error': 'assets/animations/neuro_error.json',
      }),
    ),
  ];

  static List<AvatarSpec> all() => List.unmodifiable(_avatars);

  static AvatarSpec byId(String id) {
    return _avatars.firstWhere(
      (a) => a.id == id,
      orElse: () => _avatars.firstWhere((a) => a.id == defaultAvatarId),
    );
  }
}
