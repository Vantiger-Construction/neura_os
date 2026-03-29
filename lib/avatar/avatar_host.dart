import 'package:flutter/material.dart';

import '../services/avatar_service.dart';
import 'avatar_controller.dart';
import 'avatar_registry.dart';
import 'avatar_view.dart';

/// Overlay host that keeps the avatar visible across the app.
///
/// Put this in MaterialApp.builder so it wraps every screen.
class GlobalAvatarHost extends StatefulWidget {
  final Widget child;
  final AvatarController controller;
  final AvatarService avatarService;

  /// Avatar size in logical pixels.
  final double size;

  /// Where the avatar should live on-screen.
  final Alignment alignment;

  /// Padding from screen edges.
  final EdgeInsets padding;

  /// Optional tap handler.
  final VoidCallback? onTap;

  const GlobalAvatarHost({
    super.key,
    required this.child,
    required this.controller,
    required this.avatarService,
    this.size = 120,
    this.alignment = Alignment.bottomRight,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
  });

  @override
  State<GlobalAvatarHost> createState() => _GlobalAvatarHostState();
}

class _GlobalAvatarHostState extends State<GlobalAvatarHost> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        SafeArea(
          child: Align(
            alignment: widget.alignment,
            child: Padding(
              padding: widget.padding,
              child: ValueListenableBuilder<String>(
                valueListenable: widget.avatarService.selectedAvatarId,
                builder: (_, id, __) {
                  final spec = AvatarRegistry.byId(id);
                  return GestureDetector(
                    onTap: widget.onTap,
                    child: Material(
                      color: Colors.transparent,
                      child: AvatarView(
                        spec: spec,
                        controller: widget.controller,
                        size: widget.size,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
