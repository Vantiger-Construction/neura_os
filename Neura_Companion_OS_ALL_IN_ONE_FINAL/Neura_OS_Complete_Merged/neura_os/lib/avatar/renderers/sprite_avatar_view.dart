import 'package:flutter/material.dart';

import '../avatar_asset.dart';

class SpriteAvatarView extends StatefulWidget {
  final AvatarSpec spec;
  final double size;
  final BoxFit fit;
  final Widget fallback;

  const SpriteAvatarView({
    super.key,
    required this.spec,
    this.size = 128,
    this.fit = BoxFit.contain,
    required this.fallback,
  });

  @override
  State<SpriteAvatarView> createState() => _SpriteAvatarViewState();
}

class _SpriteAvatarViewState extends State<SpriteAvatarView> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void didUpdateWidget(covariant SpriteAvatarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec.sprite?.frames.length != widget.spec.sprite?.frames.length ||
        oldWidget.spec.sprite?.fps != widget.spec.sprite?.fps) {
      _setup();
    }
  }

  void _setup() {
    _controller?.dispose();
    final cfg = widget.spec.sprite;
    final frames = cfg?.frames ?? const <String>[];
    final fps = (cfg?.fps ?? 12).clamp(1, 60);
    if (frames.isEmpty) {
      _controller = null;
      return;
    }
    final durationMs = (1000 * (frames.length / fps)).round();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    )..repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.spec.sprite;
    final frames = cfg?.frames ?? const <String>[];
    final c = _controller;
    if (frames.isEmpty || c == null) return widget.fallback;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: c,
        builder: (_, __) {
          final idx = ((c.value * frames.length).floor()) % frames.length;
          return Image.asset(
            frames[idx],
            fit: widget.fit,
            errorBuilder: (_, __, ___) => widget.fallback,
          );
        },
      ),
    );
  }
}
