import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../models/ai_avatar.dart';
import '../services/avatar_service.dart';

/// Small animated mascot widget.
///
/// This is intentionally defensive: missing assets should NOT crash the app.
class MascotWidget extends StatefulWidget {
  const MascotWidget({super.key, this.size = 100});

  final double size;

  @override
  State<MascotWidget> createState() => _MascotWidgetState();
}

class _MascotWidgetState extends State<MascotWidget> {
  final _avatarService = AvatarService();
  AIAvatar? _avatar;

  @override
  void initState() {
    super.initState();
    _avatarService.getSelectedAvatar().then((a) {
      if (!mounted) return;
      setState(() => _avatar = a);
    });
  }

  Future<bool> _assetExists(String path) async {
    try {
      await rootBundle.load(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _avatar;
    if (avatar == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<bool>(
      future: _assetExists(avatar.assetPath),
      builder: (context, snap) {
        final ok = snap.data == true;

        if (ok && avatar.assetPath.toLowerCase().endsWith('.json')) {
          return Lottie.asset(avatar.assetPath, width: widget.size, height: widget.size);
        }

        return Image.asset(
          'assets/images/ai_avatar.png',
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.35),
              ),
              alignment: Alignment.center,
              child: Text(
                'N',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            );
          },
        );
      },
    );
  }
}
