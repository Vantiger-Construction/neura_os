import '../models/ai_avatar.dart';
import 'package:flutter/foundation.dart';

class AvatarService {
  AvatarService();

  static final AvatarService instance = AvatarService();
  final ValueNotifier<String> selectedAvatarId = ValueNotifier<String>('neura');

  Future<void> init() async {
    final selected = await getSelectedAvatar();
    selectedAvatarId.value = selected.id;
  }

  /// Returns available AI Avatars.
  ///
  /// NOTE: We keep this offline‑friendly. If/when you add Lottie/Rive again,
  /// just swap the assetPath to your animation file.
  List<AIAvatar> getAvailableAvatars() {
    return const [
      AIAvatar(
          id: 'neura', name: 'Neura', assetPath: 'assets/images/ai_avatar.png'),
      AIAvatar(
          id: 'neuro', name: 'Neuro', assetPath: 'assets/images/ai_avatar.png'),
    ];
  }

  /// Persist selected avatar ID
  Future<void> selectAvatar(String id) async {
    selectedAvatarId.value = id;
    // TODO: save to storage
  }

  /// Load selected avatar
  Future<AIAvatar> getSelectedAvatar() async {
    // TODO: fetch from storage, default to Neura
    final all = getAvailableAvatars();
    return all.firstWhere(
      (a) => a.id == selectedAvatarId.value,
      orElse: () => all.first,
    );
  }
}
