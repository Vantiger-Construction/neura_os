import 'package:flutter/material.dart';

import '../avatar_asset.dart';
import '../avatar_controller.dart';

// Rive requires the ClangCL toolset on Windows which is not in the beta
// build environment. This stub passes the fallback widget through so
// AvatarView's normal asset-resolution fallback chain keeps working.
class RiveAvatarView extends StatelessWidget {
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
  Widget build(BuildContext context) => fallback;
}
