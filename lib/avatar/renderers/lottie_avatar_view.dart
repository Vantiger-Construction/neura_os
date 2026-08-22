import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../avatar_asset.dart';
import '../avatar_controller.dart';

class LottieAvatarView extends StatelessWidget {
  final AvatarSpec spec;
  final AvatarController controller;
  final double size;
  final BoxFit fit;
  final Widget fallback;

  const LottieAvatarView({
    super.key,
    required this.spec,
    required this.controller,
    this.size = 128,
    this.fit = BoxFit.contain,
    required this.fallback,
  });

  String _pickAsset() {
    final cfg = spec.lottie;
    final variants = cfg?.variants ?? const <String, String>{};

    final s = controller.signals;
    if (s.isError && variants.containsKey('error')) return variants['error']!;
    if (s.isTalking && variants.containsKey('talk')) return variants['talk']!;
    if (s.isListening && variants.containsKey('listen')) {
      return variants['listen']!;
    }
    if (s.isThinking && variants.containsKey('think')) {
      return variants['think']!;
    }
    if (variants.containsKey('idle')) return variants['idle']!;
    return spec.assetPath;
  }

  @override
  Widget build(BuildContext context) {
    final asset = _pickAsset();
    return SizedBox(
      width: size,
      height: size,
      child: LottieBuilder.asset(
        asset,
        fit: fit,
        repeat: true,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
