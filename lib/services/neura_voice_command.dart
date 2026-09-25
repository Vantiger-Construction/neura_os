/// Foreground chat controls recognized from a completed, addressed phrase.
///
/// This allowlist does not grant model, memory, microphone, or action approval.
/// Ordinary speech continues through the existing chat approval flow.
enum NeuraVoiceCommand {
  help('voice help'),
  stopListening('stop listening'),
  stopSpeaking('stop speaking'),
  muteReplies('mute replies'),
  unmuteReplies('unmute replies'),
  quietMode('quiet mode'),
  balancedMode('balanced mode'),
  companionMode('companion mode'),
  coachMode('coach mode'),
  openJournal('open journal'),
  openMood('open mood check-in'),
  openSettings('open settings'),
  openVoiceSettings('open voice settings');

  const NeuraVoiceCommand(this.phrase);

  final String phrase;

  static final _address = RegExp(
    r'^(?:hey\s+)?neura(?:\s*[,!:]\s*|\s+)(.+)$',
    caseSensitive: false,
  );

  static NeuraVoiceCommand? parse(String transcript) {
    final normalized = transcript.trim().replaceAll(RegExp(r'\s+'), ' ');
    final match = _address.firstMatch(normalized);
    if (match == null) return null;
    var phrase = match.group(1)!.toLowerCase().trim();
    phrase = phrase.replaceFirst(RegExp(r'[.!?]+$'), '').trim();
    if (phrase.startsWith('please ')) phrase = phrase.substring(7);
    if (phrase.endsWith(' please')) {
      phrase = phrase.substring(0, phrase.length - 7);
    }
    for (final command in values) {
      if (phrase == command.phrase) return command;
    }
    return switch (phrase) {
      'help' || 'show voice commands' || 'what can i say' => help,
      'stop' || 'end conversation' || 'stop voice' => stopListening,
      'stop talking' || 'cancel reply' => stopSpeaking,
      'mute' || 'mute yourself' => muteReplies,
      'unmute' || 'unmute yourself' => unmuteReplies,
      'open my journal' || 'open journal prompt' => openJournal,
      'open mood' || 'open mood check in' || 'mood check in' => openMood,
      'switch to quiet mode' => quietMode,
      'switch to balanced mode' => balancedMode,
      'switch to companion mode' => companionMode,
      'switch to coach mode' => coachMode,
      _ => null,
    };
  }
}
