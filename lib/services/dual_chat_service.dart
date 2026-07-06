import '../models/ai_avatar.dart';

class DualChatService {
  static const _greetings = ['hello', 'hi', 'hey', 'good morning', 'good evening', 'greetings'];
  static const _farewells = ['bye', 'goodbye', 'see you', 'later', 'farewell'];
  static const _howAreYou = ['how are you', 'how do you feel', 'how are things'];

  static const _neuraReplies = [
    'I hear you. Would you like to explore that feeling a little deeper?',
    'That sounds meaningful. What came up for you as you said that?',
    'Thank you for sharing. How long have you been carrying this?',
    'I am here with you. What do you need most right now?',
    'Your feelings are valid. What would feel supportive in this moment?',
  ];
  static const _neuroReplies = [
    'Interesting perspective. Have you considered approaching it from a different angle?',
    'Let us think this through step by step. What is the core challenge here?',
    'That is worth examining more closely. What evidence supports that belief?',
    'Good question. What outcome are you hoping for?',
    'I am processing that. What matters most to you about this situation?',
  ];

  /// Sends [message] to the local AI and returns a contextual response.
  /// Replace the body with a real API call when credentials are available.
  Future<String> sendMessage(String message, AIAvatar avatar) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final lower = message.toLowerCase();

    if (_greetings.any(lower.contains)) {
      return 'Hello! I am . How are you feeling today?';
    }
    if (_farewells.any(lower.contains)) {
      return 'Take care of yourself. I am here whenever you need to talk.';
    }
    if (_howAreYou.any(lower.contains)) {
      return 'I am fully present and here for you. More importantly — how are you?';
    }

    final pool = avatar.id == 'neuro' ? _neuroReplies : _neuraReplies;
    final idx = DateTime.now().millisecondsSinceEpoch % pool.length;
    return pool[idx];
  }
}
