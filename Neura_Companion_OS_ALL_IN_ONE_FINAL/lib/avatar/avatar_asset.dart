import 'package:flutter/foundation.dart';

import 'avatar_types.dart';

@immutable
class AvatarSpec {
  final String id;
  final String name;
  final AvatarFormat format;

  /// Primary asset path (e.g. assets/rive/neura.riv, assets/animations/neura_idle.json)
  final String assetPath;

  /// Optional fallback asset path. If missing or fails to load, we fall back to a built-in placeholder.
  final String? fallbackAssetPath;

  /// Optional format-specific configuration.
  final AvatarRiveConfig? rive;
  final AvatarLottieConfig? lottie;
  final AvatarSpriteConfig? sprite;

  const AvatarSpec({
    required this.id,
    required this.name,
    required this.format,
    required this.assetPath,
    this.fallbackAssetPath,
    this.rive,
    this.lottie,
    this.sprite,
  });
}

@immutable
class AvatarRiveConfig {
  /// Artboard to use. If null, Rive's default artboard is used.
  final String? artboard;

  /// State machine to drive. If null or missing, we render the artboard without a controller.
  final String? stateMachine;

  /// Maps canonical names (see [AvatarRiveInputs]) to actual input names inside the .riv file.
  ///
  /// Example:
  /// { AvatarRiveInputs.isTalking: 'Talking', AvatarRiveInputs.mood: 'Mood' }
  final Map<String, String> inputNames;

  const AvatarRiveConfig({
    this.artboard,
    this.stateMachine,
    this.inputNames = const {},
  });
}

@immutable
class AvatarLottieConfig {
  /// Optional alternate animation assets keyed by state.
  ///
  /// Common keys:
  ///  - 'idle'
  ///  - 'talk'
  ///  - 'listen'
  ///  - 'think'
  ///  - 'error'
  final Map<String, String> variants;

  const AvatarLottieConfig({this.variants = const {}});
}

@immutable
class AvatarSpriteConfig {
  /// Sprite frame asset paths (ordered).
  final List<String> frames;

  /// Frames per second.
  final double fps;

  const AvatarSpriteConfig({
    required this.frames,
    this.fps = 12,
  });
}
