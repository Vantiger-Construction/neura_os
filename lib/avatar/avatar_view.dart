import 'package:flutter/material.dart';

import 'asset_guard.dart';
import 'avatar_asset.dart';
import 'avatar_controller.dart';
import 'avatar_types.dart';
import 'renderers/lottie_avatar_view.dart';
import 'renderers/rive_avatar_view.dart';
import 'renderers/sprite_avatar_view.dart';

class AvatarView extends StatelessWidget {
  final AvatarSpec spec;
  final AvatarController controller;
  final double size;
  final BoxFit fit;

  const AvatarView({
    super.key,
    required this.spec,
    required this.controller,
    this.size = 128,
    this.fit = BoxFit.contain,
  });

  Widget _placeholder(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Icon(Icons.android, size: size * 0.45),
    );
  }

  AvatarFormat _inferFormatFromPath(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.riv')) return AvatarFormat.rive;
    if (p.endsWith('.json')) return AvatarFormat.lottie;
    if (p.endsWith('.png') ||
        p.endsWith('.jpg') ||
        p.endsWith('.jpeg') ||
        p.endsWith('.webp')) {
      return AvatarFormat.image;
    }
    return spec.format;
  }

  Future<_Resolved> _resolve() async {
    // Primary
    if (await AssetGuard.exists(spec.assetPath)) {
      return _Resolved(spec.format, spec.assetPath);
    }

    // Spec-level fallback
    final fb = spec.fallbackAssetPath;
    if (fb != null && await AssetGuard.exists(fb)) {
      return _Resolved(_inferFormatFromPath(fb), fb);
    }

    // If the primary format is Rive but we have Lottie variants, prefer those.
    final variants = spec.lottie?.variants ?? const <String, String>{};
    final idle = variants['idle'];
    if (idle != null && await AssetGuard.exists(idle)) {
      return _Resolved(AvatarFormat.lottie, idle);
    }

    // No animated asset installed: use her full-body art, animated
    // procedurally by NeuraAnimatedBody.
    if (await AssetGuard.exists(kNeuraBodyArt)) {
      return const _Resolved(AvatarFormat.image, kNeuraBodyArt);
    }

    return const _Resolved(null, null);
  }

  @override
  Widget build(BuildContext context) {
    final fallback = _placeholder(context);

    return FutureBuilder<_Resolved>(
      future: _resolve(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return SizedBox(
            width: size,
            height: size,
            child:
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final resolved = snap.data!;
        final format = resolved.format;
        final path = resolved.path;
        if (format == null || path == null) return fallback;

        switch (format) {
          case AvatarFormat.rive:
            final adjusted = (path == spec.assetPath)
                ? spec
                : AvatarSpec(
                    id: spec.id,
                    name: spec.name,
                    format: AvatarFormat.rive,
                    assetPath: path,
                    fallbackAssetPath: spec.fallbackAssetPath,
                    rive: spec.rive,
                    lottie: spec.lottie,
                    sprite: spec.sprite,
                  );
            return RiveAvatarView(
              spec: adjusted,
              controller: controller,
              size: size,
              fit: fit,
              fallback: fallback,
            );
          case AvatarFormat.lottie:
            // Render using spec.lottie variants, but ensure spec.assetPath points to the resolved path.
            final adjusted = AvatarSpec(
              id: spec.id,
              name: spec.name,
              format: AvatarFormat.lottie,
              assetPath: path,
              fallbackAssetPath: spec.fallbackAssetPath,
              lottie: spec.lottie,
            );
            return AnimatedBuilder(
              animation: controller,
              builder: (_, __) => LottieAvatarView(
                spec: adjusted,
                controller: controller,
                size: size,
                fit: fit,
                fallback: fallback,
              ),
            );
          case AvatarFormat.sprite:
            return SpriteAvatarView(
                spec: spec, size: size, fit: fit, fallback: fallback);
          case AvatarFormat.image:
            return SizedBox(
              width: size,
              height: size,
              child: Image.asset(path,
                  fit: fit,
                  cacheWidth:
                      (size * MediaQuery.devicePixelRatioOf(context)).round(),
                  cacheHeight:
                      (size * MediaQuery.devicePixelRatioOf(context)).round(),
                  errorBuilder: (_, __, ___) => fallback),
            );
        }
      },
    );
  }
}

class _Resolved {
  final AvatarFormat? format;
  final String? path;
  const _Resolved(this.format, this.path);
}
