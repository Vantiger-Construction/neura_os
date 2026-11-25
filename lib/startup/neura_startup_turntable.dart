import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const kNeuraStartupFrontAsset = 'assets/images/neura_startup_front.png';
const kNeuraStartupTurntableAsset = 'assets/images/neura_startup_turntable.png';
const kNeuraStartupTurntableFrames = 32;
const kNeuraStartupTurntableColumns = 8;
const kNeuraStartupTurntableFrameSize = Size(160, 240);
const kNeuraStartupTurntableAtlasSize = Size(1280, 960);

/// One local, bounded atlas. No runtime 3D renderer or per-frame decoding.
class NeuraStartupPortrait extends StatefulWidget {
  const NeuraStartupPortrait({
    super.key,
    required this.frame,
    required this.loadTurntable,
    required this.onTurntableReady,
    required this.width,
    required this.height,
  });

  final ValueListenable<int> frame;
  final bool loadTurntable;
  final ValueChanged<bool> onTurntableReady;
  final double width;
  final double height;

  @override
  State<NeuraStartupPortrait> createState() => _NeuraStartupPortraitState();
}

class _NeuraStartupPortraitState extends State<NeuraStartupPortrait> {
  ImageStream? _stream;
  ImageInfo? _atlas;
  late final _listener = ImageStreamListener(_onImage, onError: _onError);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(NeuraStartupPortrait oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadTurntable != widget.loadTurntable) _resolve();
  }

  void _resolve() {
    if (!widget.loadTurntable) {
      _release();
      return;
    }
    final stream = const ExactAssetImage(kNeuraStartupTurntableAsset)
        .resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    _release();
    _stream = stream..addListener(_listener);
  }

  void _reportReady(bool ready) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (!ready || _atlas != null)) {
        widget.onTurntableReady(ready);
      }
    });
  }

  void _onImage(ImageInfo info, bool synchronous) {
    if (!mounted || !widget.loadTurntable) {
      info.dispose();
      return;
    }
    if (info.image.width != kNeuraStartupTurntableAtlasSize.width ||
        info.image.height != kNeuraStartupTurntableAtlasSize.height) {
      info.dispose();
      _onError(StateError('Invalid startup turntable dimensions'), null);
      return;
    }
    setState(() {
      _atlas?.dispose();
      _atlas = info;
    });
    _reportReady(true);
  }

  void _onError(Object error, StackTrace? stack) {
    if (!mounted) return;
    setState(() {
      _atlas?.dispose();
      _atlas = null;
    });
    _reportReady(false);
  }

  void _release() {
    _stream?.removeListener(_listener);
    _stream = null;
    _atlas?.dispose();
    _atlas = null;
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final atlas = _atlas?.image;
    if (atlas != null) {
      return CustomPaint(
        painter: NeuraStartupTurntablePainter(atlas, widget.frame),
        size: Size(widget.width, widget.height),
      );
    }
    return Image.asset(
      kNeuraStartupFrontAsset,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.contain,
      cacheHeight: (widget.height * MediaQuery.devicePixelRatioOf(context))
          .ceil()
          .clamp(1, 240)
          .toInt(),
      filterQuality: FilterQuality.low,
      excludeFromSemantics: true,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.face_rounded,
        size: 72,
        color: Color(0xFFC4B5FD),
      ),
    );
  }
}

class NeuraStartupTurntablePainter extends CustomPainter {
  NeuraStartupTurntablePainter(this.atlas, this.frame) : super(repaint: frame);

  final ui.Image atlas;
  final ValueListenable<int> frame;

  Rect get sourceRect {
    final index = frame.value.clamp(0, kNeuraStartupTurntableFrames - 1).toInt();
    return Rect.fromLTWH(
      (index % kNeuraStartupTurntableColumns) *
          kNeuraStartupTurntableFrameSize.width,
      (index ~/ kNeuraStartupTurntableColumns) *
          kNeuraStartupTurntableFrameSize.height,
      kNeuraStartupTurntableFrameSize.width,
      kNeuraStartupTurntableFrameSize.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(
      BoxFit.contain,
      kNeuraStartupTurntableFrameSize,
      size,
    );
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      atlas,
      sourceRect,
      destination,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(NeuraStartupTurntablePainter oldDelegate) =>
      oldDelegate.atlas != atlas || oldDelegate.frame != frame;
}
