
import '../models/situation_playbook.dart';

class PlaybookService {
  PlaybookService._();

  static final PlaybookService instance = PlaybookService._();

  final List<SituationPlaybook> _playbooks = [
    SituationPlaybook(
      id: 'messed_up_work',
      name: 'I messed up at work',
      triggerKeywords: ['mess up', 'screwed up', 'failed', 'work mistake'],
      steps: [
        'Pause. Name the mistake without attacking yourself.',
        'Separate “what happened” from “what it means about you”.',
        'List 1–2 concrete repair steps.',
        'Decide what you\'ll do in the next 24 hours, not for the rest of your career.',
      ],
    ),
    SituationPlaybook(
      id: 'scared_to_text',
      name: 'I’m scared to text this person',
      triggerKeywords: ['text', 'message', 'afraid to text'],
      steps: [
        'Write the message you\'d send if you weren\'t scared.',
        'Remove anything that tries to over-explain or apologize too much.',
        'Add one honest sentence about how you feel.',
        'Decide: send it, schedule it, or rewrite tomorrow.',
      ],
    ),
  ];
  SituationPlaybook? detectFromText(String text) {
    final lower = text.toLowerCase();
    for (final pb in _playbooks) {
      if (pb.triggerKeywords.any((kw) => lower.contains(kw))) {
        return pb;
      }
    }
    return null;
  }

  List<SituationPlaybook> all() => List.unmodifiable(_playbooks);
}
