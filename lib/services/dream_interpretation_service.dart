class DreamInterpretationService {
  static const _symbolMap = <String, String>{
    'water':
        'Water often represents the subconscious mind and emotional states.',
    'flying': 'Flying can symbolise freedom, ambition, or a desire to escape.',
    'falling': 'Falling may reflect anxiety, loss of control, or transition.',
    'chase':
        'Being chased can point to avoidance of an issue or unresolved fear.',
    'house': 'A house frequently represents the self and your inner world.',
    'teeth': 'Teeth can relate to self-image, communication, or fear of loss.',
    'death':
        'Death in dreams often signals transformation or an ending that leads to renewal.',
    'animal':
        'Animals may embody instincts, emotions, or aspects of your personality.',
    'fire':
        'Fire can represent passion, destruction, transformation, or purification.',
    'road': 'Roads and paths symbolise direction, choices, and life journey.',
    'darkness':
        'Darkness may reflect the unknown, hidden fears, or unexplored parts of the self.',
    'light': 'Light often signals clarity, hope, or spiritual insight.',
    'ocean':
        'The ocean can represent the vastness of the unconscious and deep emotions.',
    'mountain':
        'Mountains may symbolise challenges, ambition, or spiritual ascent.',
  };

  static const _moods = <String, String>{
    'joy': 'The overall tone of this dream feels positive and uplifting.',
    'sadness':
        'This dream carries a melancholic undertone, possibly processing grief or longing.',
    'fear':
        'This dream has an anxious quality, possibly reflecting unresolved stress.',
    'anger':
        'There is tension woven through this dream, suggesting something needs your attention.',
    'calm': 'This dream has a peaceful quality, suggesting inner harmony.',
    'surprise':
        'Elements of the unexpected dominate this dream, inviting curiosity.',
  };

  /// Uses keyword matching to interpret [transcript] and return an
  /// interpretation and mood summary. Swap the body for a real AI call.
  Future<Map<String, String>> interpret(String transcript) async {
    if (transcript.trim().isEmpty) {
      return {'interpretation': '', 'moodSummary': ''};
    }
    final lower = transcript.toLowerCase();

    // Collect matched symbol interpretations.
    final matched = _symbolMap.entries
        .where((e) => lower.contains(e.key))
        .map((e) => e.value)
        .toList();

    final interpretation = matched.isNotEmpty
        ? matched.join(' ')
        : 'This dream carries personal meaning that is unique to your experience. '
            'Reflect on the feelings it evoked rather than the literal images.';

    // Detect dominant mood word.
    String moodSummary = '';
    for (final entry in _moods.entries) {
      if (lower.contains(entry.key)) {
        moodSummary = entry.value;
        break;
      }
    }
    if (moodSummary.isEmpty) {
      moodSummary = 'The emotional tone of this dream is subtle — sit with the '
          'feelings it left behind for deeper insight.';
    }

    return {'interpretation': interpretation, 'moodSummary': moodSummary};
  }
}
