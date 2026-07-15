import '../models/crisis_playbook.dart';

class CrisisPlaybookService {
  CrisisPlaybookService._internal();
  static final CrisisPlaybookService instance =
      CrisisPlaybookService._internal();

  final List<CrisisPlaybook> _playbooks = [
    const CrisisPlaybook(
      id: 'overwhelmed',
      title: 'Feeling Overwhelmed',
      description:
          'When everything piles up and your brain feels fried, this playbook '
          'helps you slow things down and choose one small next step.',
      steps: [
        'Pause and take 3–5 slow breaths. Focus on the air moving in and out.',
        'Look around and name 5 things you can see, 4 things you can touch, '
            '3 things you can hear. This helps ground your nervous system.',
        'Write down everything on your mind in a quick brain dump. No editing.',
        'Circle or highlight just ONE tiny thing you could do in the next 10 minutes.',
        "If nothing feels doable, that's okay. Your only task can be to rest "
            'or to reach out to someone you trust.',
      ],
      tags: ['overwhelmed', 'stress', 'grounding'],
    ),
    const CrisisPlaybook(
      id: 'anxiety_spike',
      title: 'Anxiety Spike',
      description:
          'For moments when your heart is racing, thoughts spiral, and your '
          'body feels on high alert.',
      steps: [
        'Remind yourself: "This feeling is intense, but it will pass."',
        'Try a simple breathing pattern: inhale for 4, exhale for 6, '
            'for about 1–3 minutes.',
        'Relax your jaw and unclench your shoulders and hands.',
        "Name what you're worried about in one sentence. Keep it short.",
        'Ask: "What is one thing I can do that is actually in my control right now?"',
        'If anxiety feels unmanageable or you feel unsafe, reach out to a '
            'trusted person or a professional for support.',
      ],
      tags: ['anxiety', 'panic', 'grounding'],
    ),
    const CrisisPlaybook(
      id: 'feeling_unsafe',
      title: 'Feeling Very Unsafe or In Danger',
      description:
          'If you feel at risk of being harmed, harming yourself, or harming '
          'someone else, your safety comes first.',
      steps: [
        'If you are in immediate danger, contact local emergency services '
            'right away.',
        'If possible, move to a safer location or be near people you trust.',
        'Reach out to a trusted contact (friend, family member, or professional) '
            'and tell them honestly that you do not feel safe.',
        'Use any crisis hotlines available in your region (such as a national '
            'mental health or crisis line) to speak with someone trained to help.',
        'After the most intense moment passes, consider writing a short note '
            'about what happened and how you got through it so Neura and your '
            'support network can help you plan for next time.',
      ],
      tags: ['safety', 'danger', 'crisis'],
    ),
    const CrisisPlaybook(
      id: 'messed_up_work',
      title: 'I Messed Up at Work',
      description:
          'For when a mistake at work is looping in your head and you need '
          'to separate the mistake from your worth.',
      steps: [
        'Pause. Name the mistake without attacking yourself.',
        'Separate "what happened" from "what it means about you".',
        'List 1-2 concrete repair steps.',
        "Decide what you'll do in the next 24 hours, not for the rest of your career.",
      ],
      tags: ['work', 'mistake', 'failed'],
    ),
    const CrisisPlaybook(
      id: 'scared_to_text',
      title: "I'm Scared to Text This Person",
      description:
          'For when you have a message you need to send but fear is keeping '
          'you from sending it.',
      steps: [
        "Write the message you'd send if you weren't scared.",
        'Remove anything that tries to over-explain or apologize too much.',
        'Add one honest sentence about how you feel.',
        'Decide: send it, schedule it, or rewrite tomorrow.',
      ],
      tags: ['text', 'message'],
    ),
  ];

  List<CrisisPlaybook> get playbooks => List.unmodifiable(_playbooks);

  CrisisPlaybook? findById(String id) {
    try {
      return _playbooks.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Word-boundary keyword match against each playbook's [CrisisPlaybook.tags]
  /// -- not a plain substring `.contains()`, which would false-positive on
  /// unrelated words like "context"/"textbook" for a tag like "text".
  CrisisPlaybook? findByKeyword(String text) {
    for (final p in _playbooks) {
      for (final tag in p.tags) {
        final pattern = RegExp(
          r'\b' + RegExp.escape(tag.replaceAll('_', ' ')) + r'\b',
          caseSensitive: false,
        );
        if (pattern.hasMatch(text)) return p;
      }
    }
    return null;
  }
}
