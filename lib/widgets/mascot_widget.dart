import 'package:flutter/material.dart';

import '../avatar/avatar_globals.dart';
import '../avatar/avatar_registry.dart';
import '../avatar/avatar_view.dart';

/// Backwards-compatible widget: shows the currently selected avatar.
///
/// Prefer using [GlobalAvatarHost] for the whole-app overlay.
class MascotWidget extends StatelessWidget {
  final double size;
  final Alignment alignment;

  const MascotWidget({
    super.key,
    this.size = 110,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ValueListenableBuilder<String>(
        valueListenable: AvatarGlobals.service.selectedAvatarId,
        builder: (_, id, __) {
          final spec = AvatarRegistry.byId(id);
          return AvatarView(
            spec: spec,
            controller: AvatarGlobals.controller,
            size: size,
          );
        },
      ),
    );
  }
}
