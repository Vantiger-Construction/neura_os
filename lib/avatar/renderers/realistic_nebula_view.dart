import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/neura_events_extra.dart';
import '../../reliability/safe_boot.dart';
import '../avatar_controller.dart';
import 'nebula_avatar_view.dart';
import 'neura_mouth_layer.dart';

/// A locally bundled, mouth-free 1024 x 1536 portrait. All patches share
/// the fitted body's coordinate space, including on compact square surfaces.
class RealisticNebulaView extends StatefulWidget {
  const RealisticNebulaView({
    super.key,
    required this.controller,
    required this.size,
    required this.enabled,
  });

  static const bodyAsset = 'assets/images/neura_realistic_body.webp';
  static const faceAsset = 'assets/images/neura_realistic_face.webp';
  final AvatarController controller;
  final double size;
  final bool enabled;

  @override
  State<RealisticNebulaView> createState() => _RealisticNebulaViewState();
}

class _RealisticNebulaViewState extends State<RealisticNebulaView>
    with WidgetsBindingObserver {
  static const _mouthBounds = Rect.fromLTWH(
    470 / 1024,
    215 / 1536,
    64 / 1024,
    40 / 1536,
  );

  ImageStream? _stream;
  late final _listener = ImageStreamListener(_onAtlas, onError: _onAtlasError);
  ImageInfo? _atlas;
  bool _failed = false;
  bool _foreground = true;
  bool _surfaceLive = false;
  Timer? _blink;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_resetBlink);
    widget.controller.addListener(_onSignal);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _surfaceLive = TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (!_surfaceLive) _resetBlink();
    final stream = const ExactAssetImage(RealisticNebulaView.faceAsset)
        .resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    _stream?.removeListener(_listener);
    _atlas?.dispose();
    _atlas = null;
    _failed = false;
    _stream = stream..addListener(_listener);
  }

  void _onAtlas(ImageInfo info, bool synchronous) {
    _atlas?.dispose();
    setState(() {
      _atlas = info;
      _failed = info.image.width != 320 || info.image.height != 72;
    });
  }

  void _onAtlasError(Object error, StackTrace? stack) {
    setState(() => _failed = true);
  }

  @override
  void didUpdateWidget(RealisticNebulaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onSignal);
      widget.controller.addListener(_onSignal);
      _resetBlink();
    }
    if (!widget.enabled) _resetBlink();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _resetBlink();
  }

  void _onSignal() {
    if (!widget.controller.signals.blink ||
        !widget.enabled ||
        !_surfaceLive ||
        !_foreground ||
        SafeBoot.instance.safeMode.value) {
      return;
    }
    _blink?.cancel();
    setState(
        () => _blink = Timer(const Duration(milliseconds: 115), _resetBlink));
  }

  void _resetBlink() {
    if (_blink == null) return;
    _blink!.cancel();
    setState(() => _blink = null);
  }

  @override
  void dispose() {
    _blink?.cancel();
    widget.controller.removeListener(_onSignal);
    SafeBoot.instance.safeMode.removeListener(_resetBlink);
    WidgetsBinding.instance.removeObserver(this);
    _stream?.removeListener(_listener);
    _atlas?.dispose();
    super.dispose();
  }

  Widget _fallback() => NebulaAvatarView(
        size: widget.size,
        controller: widget.controller,
        enabled: widget.enabled,
      );

  @override
  Widget build(BuildContext context) {
    final atlas = _atlas?.image;
    if (_failed) return _fallback();
    if (atlas == null) return SizedBox.square(dimension: widget.size);
    return Semantics(
      image: true,
      label: 'Realistic Nebula portrait',
      child: SizedBox.square(
        dimension: widget.size,
        child: Center(
            child: AspectRatio(
          aspectRatio: 1024 / 1536,
          child: LayoutBuilder(builder: (context, constraints) {
            final physicalHeight =
                constraints.maxHeight * MediaQuery.devicePixelRatioOf(context);
            // Even if Flutter caches every tier during a window resize, the
            // four RGBA bodies and shared face atlas total less than 7 MiB.
            final height = switch (physicalHeight) {
              <= 144 => 144,
              <= 384 => 384,
              <= 768 => 768,
              _ => 1344,
            };
            return Image.asset(
              RealisticNebulaView.bodyAsset,
              cacheHeight: height,
              fit: BoxFit.fill,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => FittedBox(child: _fallback()),
              frameBuilder: (_, body, frame, __) {
                if (frame == null) return const SizedBox.expand();
                return NeuraMouthLayer(
                  controller: widget.controller,
                  enabled: widget.enabled,
                  mouthBounds: _mouthBounds,
                  waitForSpeechCue: true,
                  mouthPainter: (pose) => RealisticMouthPainter(atlas, pose),
                  child: CustomPaint(
                    foregroundPainter:
                        _blink == null ? null : _EyelidPainter(atlas),
                    child: body,
                  ),
                );
              },
            );
          }),
        )),
      ),
    );
  }
}

class _EyelidPainter extends CustomPainter {
  const _EyelidPainter(this.atlas);
  final ui.Image atlas;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 1024;
    final sy = size.height / 1536;
    canvas.drawImageRect(
        atlas,
        const Rect.fromLTWH(0, 44, 100, 28),
        Rect.fromLTWH(449 * sx, 169 * sy, 100 * sx, 28 * sy),
        Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_EyelidPainter old) => atlas != old.atlas;
}

/// Tiles in the local face atlas: rest, pressed, rounded, open and lip-to-teeth.
class RealisticMouthPainter extends CustomPainter {
  const RealisticMouthPainter(this.atlas, this.pose);
  final ui.Image atlas;
  final NeuraMouthPose pose;

  int get tile {
    if (pose.viseme == NeuraViseme.MBP) return 1;
    if (pose.open == 0) return 0;
    return switch (pose.viseme) {
      NeuraViseme.O ||
      NeuraViseme.U ||
      NeuraViseme.WQ ||
      NeuraViseme.R ||
      NeuraViseme.CHJSH =>
        2,
      NeuraViseme.FV => 4,
      _ => 3,
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final dest = Offset.zero & size;
    canvas.drawImageRect(atlas, const Rect.fromLTWH(0, 0, 64, 40), dest, paint);
    final index = tile;
    if (index == 0) return;
    paint.color = Colors.white.withValues(alpha: index == 1 ? 1 : pose.open);
    canvas.drawImageRect(
        atlas, Rect.fromLTWH(index * 64.0, 0, 64, 40), dest, paint);
  }

  @override
  bool shouldRepaint(RealisticMouthPainter old) =>
      atlas != old.atlas || pose != old.pose;
}
