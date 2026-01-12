import 'package:flutter/material.dart';

// import 'package:rive/rive.dart';

import '../avatar_asset.dart';
import '../avatar_controller.dart';

class RiveAvatarView extends StatefulWidget {
  final AvatarSpec spec;
  final AvatarController controller;
  final double size;
  final BoxFit fit;
  final Widget fallback;

  const RiveAvatarView({
    super.key,
    required this.spec,
    required this.controller,
    this.size = 128,
    this.fit = BoxFit.contain,
    required this.fallback,
  });

  @override
  State<RiveAvatarView> createState() => _RiveAvatarViewState();
}

class _RiveLoaded {
  final dynamic artboard;
  final Map<String, dynamic> inputs;

  _RiveLoaded(this.artboard, this.inputs);
}

class _RiveAvatarViewState extends State<RiveAvatarView> {
  @override
  Widget build(BuildContext context) {
    return widget.fallback; // Placeholder since Rive is removed
  }
}
