import '../models/ai_avatar.dart';

class DualChatService {
  /// Sends user message to the AI and returns response from specified avatar.
  Future<String> sendMessage(String message, AIAvatar avatar) async {
    // TODO: integrate OpenAI API or other NLP service
    return 'Response from ${avatar.name}: ...';
  }
}
