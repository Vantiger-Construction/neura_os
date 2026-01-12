import 'dart:math';

import '../models/content_item.dart';
import 'content_backend.dart';

class LocalTemplateBackend implements ContentBackend {
  final Random _rng;
  LocalTemplateBackend({int? seed}) : _rng = seed == null ? Random() : Random(seed);

  @override
  Future<List<NeuraContentItem>> generateCandidates({
    required Map<String, dynamic> signals,
    int count = 5,
  }) async {
    final mood = (signals['mood'] ?? 'neutral').toString().toLowerCase();
    final energy = (signals['energy'] is num) ? (signals['energy'] as num).toDouble() : 0.5;
    final topIntent = (signals['topIntent'] ?? signals['top_intent'] ?? 'balance').toString().toLowerCase();

    final pool = <NeuraContentItem>[];

    // Reflection prompts
    pool.add(NeuraContentItem(
      id: _id('reflect'),
      type: NeuraContentType.reflectionPrompt,
      title: 'Quick reflection (90 seconds)',
      body: _pick([
        'Name one thing you handled better than you used to. What changed?',
        'What feeling is loudest right now? If it had a message, what would it say?',
        'What is one tiny win from today that deserves a nod?',
      ]),
      actions: const ['Start', 'Skip'],
      meta: {'mood': mood, 'energy': energy, 'intent': topIntent},
    ));

    // Mini-lesson
    pool.add(NeuraContentItem(
      id: _id('lesson'),
      type: NeuraContentType.miniLesson,
      title: 'Mini-lesson: friction is a feature',
      body: _pick([
        'When something feels hard, your brain is updating. Try: do it badly for 2 minutes, then stop. That counts.',
        'Motivation is unreliable. Environment is not. Move the next action closer by 1 step.',
        'Feelings are weather, not identity. Acknowledge them, then choose a small action anyway.',
      ]),
      actions: const ['Save', 'Try it'],
      meta: {'mood': mood, 'energy': energy, 'intent': topIntent},
    ));

    // Ritual (adapts to energy)
    pool.add(NeuraContentItem(
      id: _id('ritual'),
      type: NeuraContentType.ritual,
      title: energy < 0.35 ? 'Low-energy reset ritual (3 min)' : 'Momentum ritual (5 min)',
      body: energy < 0.35
          ? '1) Drink water. 2) Sit tall. 3) 4 slow breaths. 4) Choose ONE task and make it 10% smaller.'
          : '1) Stand up. 2) 10 deep breaths. 3) Write the next 1 action. 4) Start a 5-minute timer and begin.',
      actions: const ['Launch Ritual', 'Later'],
      meta: {'mood': mood, 'energy': energy, 'intent': topIntent},
    ));

    // Micro-quest (aligned to intent)
    pool.add(NeuraContentItem(
      id: _id('quest'),
      type: NeuraContentType.microQuest,
      title: 'Micro-quest: $topIntent',
      body: _questFor(topIntent),
      actions: const ['Accept', 'Decline'],
      meta: {'mood': mood, 'energy': energy, 'intent': topIntent},
    ));

    // Joy moment (light entertainment)
    pool.add(NeuraContentItem(
      id: _id('joy'),
      type: NeuraContentType.joyMoment,
      title: 'Joy moment (no pressure)',
      body: _pick([
        'Two-minute “caption this”: pick any object near you and give it the most dramatic movie title possible.',
        'Quick game: name 3 things you can see, 2 you can feel, 1 you can hear — then smile at your nervous system.',
        'Tiny creativity: write a one-sentence story that starts with “In Neura’s penthouse, the coffee machine became sentient…”',
      ]),
      actions: const ['Do it', 'Skip'],
      meta: {'mood': mood, 'energy': energy, 'intent': topIntent},
    ));

    pool.shuffle(_rng);
    return pool.take(count.clamp(1, pool.length)).toList(growable: false);
  }

  String _pick(List<String> options) => options[_rng.nextInt(options.length)];

  String _id(String prefix) {
    final n = _rng.nextInt(1 << 30).toRadixString(16);
    return '${prefix}_$n';
  }

  String _questFor(String intent) {
    switch (intent) {
      case 'focus':
        return 'Pick one task. Set a 7-minute timer. Do only the first step. Stop when the timer ends.';
      case 'calm':
      case 'stress':
        return 'Do 5 slow exhales (exhale longer than inhale). Then loosen your jaw and shoulders.';
      case 'confidence':
        return 'Write a 1-line “proof of progress” from this week. Read it out loud once.';
      case 'connection':
        return 'Send one kind message to someone. Keep it short. No expectations.';
      default:
        return 'Do one 2-minute action that makes tomorrow easier: tidy 1 surface, prep 1 item, or write 1 reminder.';
    }
  }
}
