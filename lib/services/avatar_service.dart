import 'package:flutter/foundation.dart';
import '../avatar/avatar_registry.dart';
import '../models/ai_avatar.dart';
import '../startup/neura_prefs_cache.dart';

class AvatarService {
  AvatarService._();
  factory AvatarService() => instance;

  @visibleForTesting
  AvatarService.forTesting();

  static final AvatarService instance = AvatarService._();

  static const _kSelectedKey = 'avatar_selected_id';
  bool _saving = false;
  bool _suspended = false;
  bool _cacheTrusted = true;
  Future<bool>? _pending;
  int _generation = 0;

  final ValueNotifier<String> selectedAvatarId = ValueNotifier<String>('neura');

  Future<void> init() async {
    await getSelectedAvatar();
  }

  /// Returns available AI Avatars.
  List<AIAvatar> getAvailableAvatars() {
    return AvatarRegistry.all()
        .map((a) => AIAvatar(id: a.id, name: a.name, assetPath: a.assetPath))
        .toList(growable: false);
  }

  /// Persists selected avatar ID to shared preferences.
  Future<bool> selectAvatar(String id) {
    if (_suspended ||
        _saving ||
        !getAvailableAvatars().any((a) => a.id == id)) {
      return Future.value(false);
    }
    _saving = true;
    final operation = _persistSelection(id, _generation);
    _pending = operation;
    return operation.whenComplete(() {
      if (identical(_pending, operation)) _pending = null;
      _saving = false;
    });
  }

  Future<bool> _persistSelection(String id, int generation) async {
    try {
      if (!await NeuraPrefsCache.prefs.setString(_kSelectedKey, id)) {
        throw StateError('Avatar selection could not be saved.');
      }
      if (generation != _generation) return false;
      _cacheTrusted = true;
      selectedAvatarId.value = id;
      return true;
    } catch (_) {
      // SharedPreferences updates its cache before storage acknowledges a write.
      _cacheTrusted = false;
      try {
        await NeuraPrefsCache.prefs.reload();
        _cacheTrusted = true;
      } catch (_) {
        // Retain the last confirmed visible selection.
      }
      return false;
    }
  }

  /// Loads selected avatar from shared preferences, defaulting to Neura.
  Future<AIAvatar> getSelectedAvatar() async {
    final id = _suspended || _saving || !_cacheTrusted
        ? selectedAvatarId.value
        : NeuraPrefsCache.prefs.getString(_kSelectedKey) ??
            AvatarRegistry.defaultAvatarId;
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
    _suspended = true;
    _generation++;
    selectedAvatarId.value = AvatarRegistry.defaultAvatarId;
  }

  /// A submitted platform write cannot be cancelled. Never clear preferences
  /// underneath it; a timeout leaves removal incomplete and this writer closed.
  Future<void> drainForDataWipe() async {
    await _pending?.timeout(const Duration(seconds: 3));
  }

  @visibleForTesting
  void resetForTesting() {
    if (_pending != null) throw StateError('Avatar writes have not drained.');
    _generation++;
    _suspended = false;
    _cacheTrusted = true;
    selectedAvatarId.value = AvatarRegistry.defaultAvatarId;
  }
}
