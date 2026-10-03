/// Foreground chat controls recognized from a completed, addressed phrase.
///
/// This allowlist does not grant model, memory, microphone, or action approval.
/// Ordinary speech continues through the existing chat approval flow.
enum NeuraVoiceCommand {
  help('voice help', 'Show the available voice commands.'),
  stopListening('stop listening', 'End listening and interrupt the reply.'),
  stopSpeaking('stop speaking', 'Stop the reply and chat listening.'),
  muteReplies('mute replies', 'Mute spoken replies in this chat.'),
  unmuteReplies(
      'unmute replies', 'Unmute if reply speech is enabled in settings.'),
  chooseCompanion(
      'choose companion', 'Open the companion picker; tap to choose.'),
  scrollUp('scroll up', 'Move up through this chat.'),
  scrollDown('scroll down', 'Move down through this chat.'),
  scrollToTop('scroll to top', 'Show the first messages in this chat.'),
  scrollToBottom('scroll to bottom', 'Show the latest messages in this chat.'),
  quietMode('quiet mode', 'Use brief replies.',
      group: NeuraVoiceCommandGroup.modes),
  balancedMode('balanced mode', 'Use the default conversational style.',
      group: NeuraVoiceCommandGroup.modes),
  companionMode('companion mode', 'Use the warmer companion style.',
      group: NeuraVoiceCommandGroup.modes),
  coachMode('coach mode', 'Use the practical next-step style.',
      group: NeuraVoiceCommandGroup.modes),
  whereAmI('where am i', 'Show the current Neura room.',
      group: NeuraVoiceCommandGroup.rooms),
  openPenthouse('open penthouse', 'Move to the Penthouse.',
      group: NeuraVoiceCommandGroup.rooms),
  openReflectionBay('open reflection bay', 'Move to Reflection Bay.',
      group: NeuraVoiceCommandGroup.rooms),
  openJoyLounge('open joy lounge', 'Move to the Joy Lounge.',
      group: NeuraVoiceCommandGroup.rooms),
  openMoodDen('open mood den', 'Move to the Mood Den.',
      group: NeuraVoiceCommandGroup.rooms),
  openDreamAtrium('open dream atrium', 'Move to the Dream Atrium.',
      group: NeuraVoiceCommandGroup.rooms),
  openLegacyVault('open legacy vault', 'Move to the Legacy Vault.',
      group: NeuraVoiceCommandGroup.rooms),
  openJournal('open journal', 'Open local journal prompts.',
      group: NeuraVoiceCommandGroup.screens),
  openMood('open mood check-in', 'Open the mood form; tap Save to record it.',
      group: NeuraVoiceCommandGroup.screens),
  openMoodHistory('open mood history', 'View saved mood check-ins.',
      group: NeuraVoiceCommandGroup.screens),
  openWeeklyReview(
      'open weekly review', 'View local reviews; tap Generate to make one.',
      group: NeuraVoiceCommandGroup.screens),
  openDreamJournal('open dream journal', 'View the dream journal calendar.',
      group: NeuraVoiceCommandGroup.screens),
  openFocus('open focus', 'Open Focus Office; tap a mode to choose it.',
      group: NeuraVoiceCommandGroup.screens),
  openQuests('open quests', 'View quests without marking any complete.',
      group: NeuraVoiceCommandGroup.screens),
  openTimeline('open timeline', 'View your local life timeline.',
      group: NeuraVoiceCommandGroup.screens),
  openSettings('open settings', 'Open Settings.',
      group: NeuraVoiceCommandGroup.screens),
  openVoiceSettings(
      'open voice settings', 'Open voice and reply-speech settings.',
      group: NeuraVoiceCommandGroup.screens),
  openAccessibility(
      'open accessibility', 'Open comfort and readability settings.',
      group: NeuraVoiceCommandGroup.screens),
  openThemes('open themes', 'Open theme and appearance settings.',
      group: NeuraVoiceCommandGroup.screens),
  openPrivacy('open privacy', 'Open Privacy & Safety settings.',
      group: NeuraVoiceCommandGroup.screens),
  openNotifications(
      'open notifications', 'Open notification settings without enabling them.',
      group: NeuraVoiceCommandGroup.screens),
  openHelp('open help', 'Open the Getting Started guide.',
      group: NeuraVoiceCommandGroup.screens),
  guidedSupport(
      'help me through this', 'Choose a short, local support activity.',
      group: NeuraVoiceCommandGroup.screens),
  removeSelectedContext('remove selected context',
      'Remove the text file selected for the next reply.',
      group: NeuraVoiceCommandGroup.context),
  excludeMemories('exclude memories',
      'Uncheck memories for the next reply; saved memories stay intact.',
      group: NeuraVoiceCommandGroup.context);

  const NeuraVoiceCommand(this.phrase, this.description,
      {this.group = NeuraVoiceCommandGroup.controls});

  final String phrase;
  final String description;
  final NeuraVoiceCommandGroup group;

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
    'show mood history': openMoodHistory,
    'open my mood history': openMoodHistory,
    'show weekly review': openWeeklyReview,
    'open my weekly review': openWeeklyReview,
    'open dream calendar': openDreamJournal,
    'open my dream journal': openDreamJournal,
    'open focus office': openFocus,
    'open my quests': openQuests,
    'show quests': openQuests,
    'open life timeline': openTimeline,
    'show my timeline': openTimeline,
    'open accessibility settings': openAccessibility,
    'open appearance': openThemes,
    'open theme settings': openThemes,
    'open privacy settings': openPrivacy,
    'open privacy and safety': openPrivacy,
    'open notification settings': openNotifications,
    'open getting started': openHelp,
    'open guided support': guidedSupport,
    'i need a moment': guidedSupport,
    'choose a companion': chooseCompanion,
    'open companion picker': chooseCompanion,
    'page up': scrollUp,
    'page down': scrollDown,
    'go to first message': scrollToTop,
    'show first message': scrollToTop,
    'go to latest message': scrollToBottom,
    'show latest message': scrollToBottom,
    'remove selected file': removeSelectedContext,
    'detach selected file': removeSelectedContext,
    "don't use memories": excludeMemories,
    'do not use memories': excludeMemories,
    'no memories for the next reply': excludeMemories,
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
    final normalized =
        transcript.trim().replaceAll(_spaces, ' ').replaceAll('’', "'");
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

enum NeuraVoiceCommandGroup {
  controls('Chat controls'),
  modes('Conversation style'),
  rooms('Neura rooms'),
  screens('Open a screen'),
  context('Next reply context');

  const NeuraVoiceCommandGroup(this.label);
  final String label;
}
