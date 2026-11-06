import 'package:flutter/foundation.dart';
import '../avatar/avatar_registry.dart';
import '../models/ai_avatar.dart';
import '../startup/neura_prefs_cache.dart';

class AvatarService {
  AvatarService();

  static final AvatarService instance = AvatarService();

  static const _kSelectedKey = 'avatar_selected_id';
  bool _saving = false;
  int _generation = 0;

  final ValueNotifier<String> selectedAvatarId = ValueNotifier<String>('neura');

  Future<void> init() async {
    final selected = await getSelectedAvatar();
    selectedAvatarId.value = selected.id;
  }

  /// Returns available AI Avatars.
  List<AIAvatar> getAvailableAvatars() {
    return AvatarRegistry.all()
        .map((a) => AIAvatar(id: a.id, name: a.name, assetPath: a.assetPath))
        .toList(growable: false);
  }

  /// Persists selected avatar ID to shared preferences.
  Future<bool> selectAvatar(String id) async {
    if (_saving || !getAvailableAvatars().any((a) => a.id == id)) return false;
    _saving = true;
    final generation = _generation;
    try {
      if (!await NeuraPrefsCache.prefs.setString(_kSelectedKey, id)) {
        throw StateError('Avatar selection could not be saved.');
      }
      if (generation != _generation) return false;
      selectedAvatarId.value = id;
      return true;
    } catch (_) {
      // SharedPreferences updates its cache before storage acknowledges a write.
      try {
        await NeuraPrefsCache.prefs.reload();
      } catch (_) {
        // Retain the last confirmed visible selection.
      }
      return false;
    } finally {
      _saving = false;
    }
  }

  /// Loads selected avatar from shared preferences, defaulting to Neura.
  Future<AIAvatar> getSelectedAvatar() async {
    final prefs = NeuraPrefsCache.prefs;
    final id = _saving
        ? selectedAvatarId.value
        : prefs.getString(_kSelectedKey) ?? AvatarRegistry.defaultAvatarId;
    final all = getAvailableAvatars();
    final avatar = all.firstWhere(
      (a) => a.id == id,
      orElse: () =>
          all.firstWhere((a) => a.id == AvatarRegistry.defaultAvatarId),
    );
    selectedAvatarId.value = avatar.id;
    return avatar;
  }

  void resetAfterDataWipe() {
    _generation++;
    selectedAvatarId.value = AvatarRegistry.defaultAvatarId;
  }
}
