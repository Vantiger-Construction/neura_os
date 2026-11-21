/// On-device reading of the feeling in one message.
///
/// This is a hint for Neura, never a diagnosis: it runs locally, stores
/// nothing, and is phrased tentatively wherever it reaches a prompt. Crisis
/// language is handled separately by CrisisTextScan and the guardrails.
class EmotionRead {
  /// Strongest feeling, or null when there is no clear signal.
  final String? primary;

  /// A second, distinct feeling when the message is mixed.
  final String? secondary;

  /// 0..1 strength of [primary].
  final double intensity;

  /// They say "I'm fine" (or similar) while signalling otherwise, or trail
  /// off with a dismissal and nothing else.
  final bool masked;

  const EmotionRead({
    this.primary,
    this.secondary,
    this.intensity = 0,
    this.masked = false,
  });

  static const none = EmotionRead();

  /// The short, tentative cue given to a small local model, or '' when the
  /// signal is unclear. Never longer than [maxCueBytes].
  String get promptCue {
    if (primary == null) {
      return masked
          ? 'They may be less fine than they say; check in gently.'
          : '';
    }
    final strong = intensity >= 0.75 ? 'very ' : '';
    final also =
        secondary == null ? '' : ', maybe also ${adjectives[secondary]}';
    final mask = masked ? " though they say they're fine" : '';
    return 'They sound $strong${adjectives[primary]}'
        '$also$mask. Meet that first.';
  }

  /// Upper bound of [promptCue] in UTF-8 bytes (all cue text is ASCII).
  static int get maxCueBytes {
    var longest = 0;
    for (final a in adjectives.values) {
      for (final b in adjectives.values) {
        final n = 'They sound very $a, maybe also $b'
                " though they say they're fine. Meet that first."
            .length;
        if (n > longest) longest = n;
      }
    }
    return longest;
  }

  static const adjectives = {
    'joy': 'happy',
    'sadness': 'sad',
    'grief': 'grieving',
    'anger': 'frustrated',
    'anxiety': 'anxious',
    'overwhelm': 'overwhelmed',
    'exhaustion': 'exhausted',
    'loneliness': 'lonely',
    'shame': 'ashamed',
  };

  @override
  String toString() => 'EmotionRead($primary, $secondary, '
      '${intensity.toStringAsFixed(2)}, masked: $masked)';
}

class EmotionAnalysisService {
  const EmotionAnalysisService();

  // Whole-token cue words (apostrophes removed). Weight 1.
  static const _words = <String, Set<String>>{
    'joy': {
      'happy',
      'glad',
      'excited',
      'thrilled',
      'wonderful',
      'fantastic',
      'awesome',
      'yay',
      'proud',
      'delighted',
      'stoked',
      'grateful',
      'thankful',
      'relieved',
      'joyful',
      'ecstatic',
      'overjoyed',
    },
    'sadness': {
      'sad',
      'unhappy',
      'depressed',
      'miserable',
      'heartbroken',
      'crying',
      'cried',
      'tears',
      'hopeless',
      'upset',
      'gutted',
      'disappointed',
    },
    'grief': {'grief', 'grieving', 'mourning', 'funeral', 'bereaved'},
    'anger': {
      'angry',
      'furious',
      'pissed',
      'livid',
      'annoyed',
      'irritated',
      'frustrated',
      'frustrating',
      'rage',
      'infuriating',
      'unfair',
    },
    'anxiety': {
      'anxious',
      'anxiety',
      'worried',
      'worrying',
      'nervous',
      'scared',
      'afraid',
      'terrified',
      'panic',
      'panicking',
      'dread',
      'dreading',
      'stressed',
      'stressing',
      'uneasy',
      'freaking',
    },
    'overwhelm': {'overwhelmed', 'overwhelming', 'swamped', 'drowning'},
    'exhaustion': {
      'exhausted',
      'drained',
      'burnout',
      'knackered',
      'shattered',
      'depleted',
    },
    'loneliness': {'lonely', 'isolated', 'friendless', 'lonesome'},
    'shame': {'ashamed', 'embarrassed', 'humiliated', 'guilty', 'mortified'},
  };

  // Ambiguous alone ("sit down", "that's great", "I'm tired of this"), so
  // they need an intensifier or other signal before they count.
  static const _weakWords = <String, Set<String>>{
    'joy': {'great', 'amazing', 'love', 'excellent'},
    'sadness': {'down', 'hurt', 'hurting', 'empty', 'cry', 'low'},
    'anger': {'mad', 'hate', 'annoying'},
    'anxiety': {'worry', 'stress', 'tense', 'nervy'},
    'exhaustion': {'tired', 'sleepy', 'worn', 'wiped'},
    'loneliness': {'alone', 'invisible'},
  };
  static const _weakWeight = 0.6;

  // Self-criticism only counts when it is about the speaker.
  static const _selfCritical = {
    'stupid',
    'idiot',
    'useless',
    'pathetic',
    'worthless',
    'failure',
    'loser',
    'disgusting',
  };
  static const _selfWords = {'i', 'im', 'ive', 'me', 'myself', 'am', 'feel'};

  // Multi-word expressions carry more signal than any single word.
  static const _phrases = <String, Map<String, double>>{
    'sadness': {
      'feel low': 2,
      'feeling low': 2,
      'let down': 1.5,
      'miss her': 2,
      'miss him': 2,
      'miss them': 2,
      'feel like crying': 2.5,
      'nothing makes me happy': 3,
    },
    'grief': {'passed away': 3},
    'anger': {
      'fed up': 2,
      'sick of': 2,
      'so done with': 2,
      'sick and tired': 2.5,
      'drives me crazy': 2,
    },
    'anxiety': {
      "can't stop thinking": 2,
      "can't stop worrying": 3,
      "can't breathe": 2,
      'on edge': 2,
      "can't sleep": 1.5,
      'what if': 1,
    },
    'overwhelm': {
      "can't cope": 3,
      'too much': 2,
      'so much to do': 2.5,
      "don't know where to start": 2.5,
      'everything at once': 2.5,
      'falling behind': 2,
      'in over my head': 3,
    },
    'exhaustion': {
      'burnt out': 2.5,
      'burned out': 2.5,
      'running on empty': 3,
      "can't keep going": 2,
      'no energy': 2.5,
      'so tired': 2,
    },
    'loneliness': {
      'no one': 2,
      'nobody cares': 3,
      'by myself': 1.5,
      'no friends': 3,
      'left out': 2,
      'nobody to talk to': 3,
      'all alone': 2.5,
    },
    'shame': {
      'my fault': 2,
      'hate myself': 3,
      'messed up': 1.5,
      'screwed up': 1.5,
      'let everyone down': 3,
      'so embarrassing': 2.5,
    },
    'joy': {
      'good news': 2.5,
      'got the job': 3,
      'so happy': 2.5,
      "can't wait": 2,
      'best day': 3,
      'i did it': 2.5,
    },
  };

  static final _griefPattern = RegExp(
    r"\b(lost|losing) (my|our|a) (mom|mum|mother|dad|father|grandma|"
    r"grandpa|grandmother|grandfather|nan|nana|wife|husband|partner|friend|"
    r"best friend|brother|sister|son|daughter|baby|aunt|uncle|dog|cat|pet)\b"
    r"|\b(mom|mum|mother|dad|father|grandma|grandpa|nan|nana|wife|husband|"
    r"partner|friend|brother|sister|son|daughter|baby|aunt|uncle|dog|cat|"
    r"pet) (passed|died|is gone)\b"
    r"|\bsince (she|he|they) (died|passed)\b",
  );

  static const _negators = {
    'not',
    'no',
    'never',
    'isnt',
    'wasnt',
    'arent',
    'dont',
    'doesnt',
    'didnt',
    'aint',
    'hardly',
    'barely',
    'without',
  };

  static const _intensifiers = {
    'so',
    'really',
    'very',
    'extremely',
    'super',
    'totally',
    'completely',
    'utterly',
    'absolutely',
    'incredibly',
    'terribly',
    'too',
    'insanely',
    'freaking',
    'seriously',
  };

  static const _softeners = {
    'bit',
    'little',
    'slightly',
    'kinda',
    'somewhat',
    'sorta',
  };

  static final _maskPattern = RegExp(
    r"\b(i'?m|i am|it'?s|its) (fine|ok|okay|alright|all right)\b",
  );
  static final _dismissPattern = RegExp(
    r"\b(whatever|never ?mind|doesn'?t matter|it is what it is|forget it)\b",
  );
  static final _sarcasmPattern =
      RegExp(r'\b(oh great|just great|just perfect|oh wonderful|lovely)\b');
  static final _tokenPattern = RegExp(r"[a-z]+(?:'[a-z]+)?");

  /// Reads the feeling in [text]. Returns [EmotionRead.none] when the signal
  /// is too weak to act on.
  EmotionRead read(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return EmotionRead.none;
    final lower = raw.toLowerCase().replaceAll('’', "'");
    final tokens = _tokenPattern
        .allMatches(lower)
        .map((m) => m.group(0)!.replaceAll("'", ''))
        .toList();
    final scores = <String, double>{};
    void add(String emotion, double weight) =>
        scores[emotion] = (scores[emotion] ?? 0) + weight;

    // Phrases first; their tokens are not counted again as single words.
    final consumed = <int>{};
    for (final entry in _phrases.entries) {
      for (final phrase in entry.value.entries) {
        final words = phrase.key.replaceAll("'", '').split(' ');
        for (var i = 0; i + words.length <= tokens.length; i++) {
          var match = true;
          for (var k = 0; k < words.length && match; k++) {
            match = tokens[i + k] == words[k];
          }
          if (!match) continue;
          if (!_isNegated(tokens, i)) add(entry.key, phrase.value);
          for (var k = 0; k < words.length; k++) {
            consumed.add(i + k);
          }
        }
      }
    }
    if (_griefPattern.hasMatch(lower)) add('grief', 3);

    for (var i = 0; i < tokens.length; i++) {
      if (consumed.contains(i)) continue;
      final token = tokens[i];
      String? emotion;
      var weight = 1.0;
      for (final e in _words.entries) {
        if (e.value.contains(token)) emotion = e.key;
      }
      if (emotion == null) {
        for (final e in _weakWords.entries) {
          if (e.value.contains(token)) {
            emotion = e.key;
            weight = _weakWeight;
          }
        }
      }
      if (emotion == null &&
          _selfCritical.contains(token) &&
          _nearby(tokens, i, _selfWords)) {
        emotion = 'shame';
        weight = 1.5;
      }
      if (emotion == null) continue;
      if (i > 0 && _intensifiers.contains(tokens[i - 1])) weight += 0.75;
      if (i > 0 && _softeners.contains(tokens[i - 1])) weight -= 0.3;
      if (_isNegated(tokens, i)) {
        // "not happy" leans sad; "not worried" is simply not worried.
        if (emotion == 'joy') add('sadness', 1.0);
        continue;
      }
      add(emotion, weight);
    }

    // "Oh great, another deadline" is not joy when something else is wrong.
    final negativeSignal =
        scores.entries.any((e) => e.key != 'joy' && e.value > 0);
    if (negativeSignal && _sarcasmPattern.hasMatch(lower)) {
      scores.remove('joy');
    }

    final masked = _maskPattern.hasMatch(lower);
    final ranked = scores.entries.where((e) => e.value >= 1).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.isEmpty) {
      // "I'm fine..." trailing off, or "I'm fine, whatever".
      final trailing = raw.endsWith('...') || raw.endsWith('…');
      final dismissive = _dismissPattern.hasMatch(lower);
      return masked && (trailing || dismissive)
          ? const EmotionRead(masked: true)
          : EmotionRead.none;
    }

    final top = ranked.first;
    var intensity = 0.35 + 0.2 * top.value;
    final letters = raw.replaceAll(RegExp('[^A-Za-z]'), '');
    final shouting = letters.length >= 6 && letters == letters.toUpperCase();
    if ('!'.allMatches(raw).length >= 2 || shouting) intensity += 0.2;
    final secondary = ranked.length > 1 && ranked[1].value >= top.value * 0.5
        ? ranked[1].key
        : null;
    return EmotionRead(
      primary: top.key,
      secondary: secondary,
      intensity: intensity.clamp(0.0, 1.0).toDouble(),
      masked: masked && top.key != 'joy',
    );
  }

  static bool _isNegated(List<String> tokens, int index) {
    for (var j = index - 1; j >= 0 && j >= index - 3; j--) {
      final t = tokens[j];
      if (t == 'but' || t == 'though' || t == 'and') return false;
      if (_negators.contains(t)) return true;
    }
    return false;
  }

  static bool _nearby(List<String> tokens, int index, Set<String> words) {
    for (var j = index - 1; j >= 0 && j >= index - 4; j--) {
      if (words.contains(tokens[j])) return true;
    }
    return false;
  }

  /// Back-compatible single-label API: the dominant feeling or 'neutral'.
  Future<String> analyzeEmotion(String text) async =>
      read(text).primary ?? 'neutral';
}
