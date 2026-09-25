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
  openVoiceSettings('open voice settings'),
  whereAmI('where am i'),
  openPenthouse('open penthouse'),
  openReflectionBay('open reflection bay'),
  openJoyLounge('open joy lounge'),
  openMoodDen('open mood den'),
  openDreamAtrium('open dream atrium'),
  openLegacyVault('open legacy vault');

  const NeuraVoiceCommand(this.phrase);

  final String phrase;

  static final _address = RegExp(
    r'^(?:hey\s+)?neura(?:\s*[,!:]\s*|\s+)(.+)$',
    caseSensitive: false,
  );
  static final _spaces = RegExp(r'\s+');
  static final _trailingPunctuation = RegExp(r'[.!?]+$');

  // Build the allowlist once. Parsing stays exact and O(1) after
  // normalization even as more local commands are added.
  static final Map<String, NeuraVoiceCommand> _commandsByPhrase = {
    for (final command in values) command.phrase: command,
    'help': help,
    'show voice commands': help,
    'what can i say': help,
    'stop': stopListening,
    'end conversation': stopListening,
    'stop voice': stopListening,
    'stop talking': stopSpeaking,
    'cancel reply': stopSpeaking,
    'mute': muteReplies,
    'mute yourself': muteReplies,
    'unmute': unmuteReplies,
    'unmute yourself': unmuteReplies,
    'open my journal': openJournal,
    'open journal prompt': openJournal,
    'open mood': openMood,
    'open mood check in': openMood,
    'mood check in': openMood,
    'switch to quiet mode': quietMode,
    'switch to balanced mode': balancedMode,
    'switch to companion mode': companionMode,
    'switch to coach mode': coachMode,
    'where are we': whereAmI,
    'what room am i in': whereAmI,
    'which room am i in': whereAmI,
    'go home': openPenthouse,
    'take me home': openPenthouse,
    'open home': openPenthouse,
    'open the penthouse': openPenthouse,
    'go to penthouse': openPenthouse,
    'go to reflection bay': openReflectionBay,
    'open reflection': openReflectionBay,
    'go to joy lounge': openJoyLounge,
    'open joy': openJoyLounge,
    'go to mood den': openMoodDen,
    'go to dream atrium': openDreamAtrium,
    'open dream room': openDreamAtrium,
    'go to legacy vault': openLegacyVault,
    'open legacy': openLegacyVault,
  };

  static NeuraVoiceCommand? parse(String transcript) {
    final normalized = transcript.trim().replaceAll(_spaces, ' ');
    final match = _address.firstMatch(normalized);
    if (match == null) return null;
    var phrase = match.group(1)!.toLowerCase().trim();
    phrase = phrase.replaceFirst(_trailingPunctuation, '').trim();
    if (phrase.startsWith('please ')) phrase = phrase.substring(7);
    if (phrase.endsWith(' please')) {
      phrase = phrase.substring(0, phrase.length - 7);
    }
    return _commandsByPhrase[phrase];
  }
}
