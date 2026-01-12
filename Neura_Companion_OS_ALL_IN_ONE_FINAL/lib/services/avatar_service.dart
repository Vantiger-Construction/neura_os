import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../avatar/avatar_registry.dart';
import '../models/ai_avatar.dart';

class AvatarService {
  static final AvatarService instance = AvatarService._();
  AvatarService._();

  static const String _kSelectedAvatarId = 'selected_avatar_id';

  bool _inited = false;
  final ValueNotifier<String> selectedAvatarId = ValueNotifier<String>(AvatarRegistry.defaultAvatarId);

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kSelectedAvatarId);
      if (id != null && id.isNotEmpty) {
        selectedAvatarId.value = id;
      }
    } catch (_) {
      // If prefs fail, we just stay on defaults.
    }
  }

  /// Returns available AI Avatars.
  List<AIAvatar> getAvailableAvatars() {
    return AvatarRegistry.all()
        .map((s) => AIAvatar(id: s.id, name: s.name, assetPath: s.assetPath))
        .toList(growable: false);
  }

  Future<void> selectAvatar(String id) async {
    selectedAvatarId.value = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSelectedAvatarId, id);
    } catch (_) {
      // ignore
    }
  }

  Future<AIAvatar> getSelectedAvatar() async {
    await init();
    final spec = AvatarRegistry.byId(selectedAvatarId.value);
    return AIAvatar(id: spec.id, name: spec.name, assetPath: spec.assetPath);
  }
}
