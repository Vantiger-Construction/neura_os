import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../models/ai_avatar.dart';
import '../services/avatar_service.dart';

class MascotWidget extends StatefulWidget {
  @override
  _MascotWidgetState createState() => _MascotWidgetState();
}

class _MascotWidgetState extends State<MascotWidget> {
  final _avatarService = AvatarService();
  AIAvatar? _avatar;

  @override
  void initState() {
    super.initState();
    _avatarService.getSelectedAvatar().then((a) {
      setState(() => _avatar = a);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_avatar == null) return SizedBox.shrink();
    return Lottie.asset(_avatar!.assetPath, width: 100, height: 100);
  }
}
