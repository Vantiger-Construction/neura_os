import '../models/ai_avatar.dart';

class AvatarService {
  /// Returns available AI Avatars.
  ///
  /// NOTE: We keep this offline‑friendly. If/when you add Lottie/Rive again,
  /// just swap the assetPath to your animation file.
  List<AIAvatar> getAvailableAvatars() {
    return const [
      AIAvatar(id: 'neura', name: 'Neura', assetPath: 'assets/images/ai_avatar.png'),
      AIAvatar(id: 'neuro', name: 'Neuro', assetPath: 'assets/images/ai_avatar.png'),
    ];
  }

  /// Persist selected avatar ID
  Future<void> selectAvatar(String id) async {
    // TODO: save to storage
  }

  /// Load selected avatar
  Future<AIAvatar> getSelectedAvatar() async {
    // TODO: fetch from storage, default to Neura
    return getAvailableAvatars().first;
  }
}
