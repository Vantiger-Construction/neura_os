/// Content Generation Scaffold
///
/// This module is intentionally conservative: it generates *options* not commands.
/// It should be fed by MemoryGraph patterns later.

class ContentEngine {
  List<String> ritualsFor(String intent) {
    switch (intent) {
      case 'seekingCalm':
        return ['60-second breathing', 'tiny gratitude note', 'quiet walk'];
      case 'seekingProgress':
        return ['pick 1 task', '5-min focus sprint', 'review goals'];
      case 'seekingSleep':
        return ['dim lights', 'dream note', 'body scan'];
      case 'seekingConnection':
        return ['message a friend', 'kindness idea', 'reflection prompt'];
      default:
        return ['gentle check-in'];
    }
  }

  String promptFor(String intent) {
    switch (intent) {
      case 'seekingCalm':
        return 'Want to slow down for one minute?';
      case 'seekingProgress':
        return 'One small step right now—what would make you proud?';
      case 'seekingSleep':
        return 'Ready to rest? I can stay quiet.';
      case 'seekingConnection':
        return 'Want company or reflection?';
      default:
        return 'How do you want to feel next?';
    }
  }
}
