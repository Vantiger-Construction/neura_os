import 'package:flutter/foundation.dart';
import '../models/ai_avatar.dart';
import '../startup/neura_prefs_cache.dart';

class AvatarService {
  AvatarService();

  static final AvatarService instance = AvatarService();

  static const _kSelectedKey = 'avatar_selected_id';

  final ValueNotifier<String> selectedAvatarId = ValueNotifier<String>('neura');

  Future<void> init() async {
    final selected = await getSelectedAvatar();
    selectedAvatarId.value = selected.id;
  }

  /// Returns available AI Avatars.
  List<AIAvatar> getAvailableAvatars() {
    return const [
      AIAvatar(
          id: 'neura', name: 'Neura', assetPath: 'assets/images/ai_avatar.png'),
      AIAvatar(
          id: 'neuro', name: 'Neuro', assetPath: 'assets/images/ai_avatar.png'),
    ];
  }

  /// Persists selected avatar ID to shared preferences.
  Future<void> selectAvatar(String id) async {
    selectedAvatarId.value = id;
    final prefs = NeuraPrefsCache.prefs;
    await prefs.setString(_kSelectedKey, id);
  }

  /// Loads selected avatar from shared preferences, defaulting to Neura.
  Future<AIAvatar> getSelectedAvatar() async {
    final prefs = NeuraPrefsCache.prefs;
    final id = prefs.getString(_kSelectedKey) ?? 'neura';
    selectedAvatarId.value = id;
    final all = getAvailableAvatars();
    return all.firstWhere(
      (a) => a.id == id,
      orElse: () => all.first,
    );
  }

  void resetAfterDataWipe() {
    selectedAvatarId.value = 'neura';
  }
}
