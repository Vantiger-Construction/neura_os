import 'package:flutter/foundation.dart';

@immutable
class AIAvatar {
  final String id;
  final String name; // 'Neura' or 'Neuro'
  final String assetPath; // path to Lottie or image asset

  const AIAvatar({
    required this.id,
    required this.name,
    required this.assetPath,
  });
}
