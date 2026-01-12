import 'dart:ui';

import 'package:flutter/material.dart';

class PortalRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  PortalRoute({required this.page})
      : super(
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
            final fade = Tween<double>(begin: 0.0, end: 1.0).animate(curve);
            final scale = Tween<double>(begin: 0.97, end: 1.0).animate(curve);

            return FadeTransition(
              opacity: fade,
              child: ScaleTransition(
                scale: scale,
                child: AnimatedBuilder(
                  animation: curve,
                  builder: (context, _) {
                    final blur = (1 - curve.value) * 10;
                    return ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      child: child,
                    );
                  },
                ),
              ),
            );
          },
        );
}

class PortalNav {
  static Future<T?> push<T>(BuildContext context, Widget page, {required bool enabled}) {
    if (!enabled) {
      return Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    }
    return Navigator.of(context).push(PortalRoute(page: page));
  }
}
