import 'package:flutter/material.dart';
import 'joy_types.dart';

class NeuraJoyScreen extends StatelessWidget {
  const NeuraJoyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final JoyMoment? moment =
        ModalRoute.of(context)?.settings.arguments as JoyMoment?;
    final JoyMoment m = moment ??
        const JoyMoment(
          id: 'fallback',
          title: 'Joy Moment',
          description: 'A small moment. No pressure.',
          type: JoyMomentType.breathingGame,
          minutes: 1,
        );

    return Scaffold(
      appBar: AppBar(title: Text(m.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.description, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            _MomentBody(moment: m),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, {'result': 'skipped'}),
                    child: const Text('No thanks'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, {'result': 'completed'}),
                    child: const Text('Done'),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _MomentBody extends StatelessWidget {
  final JoyMoment moment;
  const _MomentBody({required this.moment});

  @override
  Widget build(BuildContext context) {
    switch (moment.type) {
      case JoyMomentType.gentleJoke:
        final joke = (moment.payload['joke'] ?? '') as String;
        return Text(joke, style: Theme.of(context).textTheme.bodyLarge);
      case JoyMomentType.gratitudeDice:
        return const Text(
            'Roll (mentally) a number 1–6 and answer the matching prompt.');
      case JoyMomentType.creativePrompt:
        return const Text('Write it down anywhere. Perfection is banned.');
      case JoyMomentType.tinyQuest:
        return const Text('Pick one. Do it. Return like a legend.');
      case JoyMomentType.musicMood:
        return const Text(
            'Play a track that matches your mood. No skipping shame.');
      case JoyMomentType.breathingGame:
        final pattern = (moment.payload['pattern'] ?? '4-4-4-4') as String;
        return Text('Breathing pattern: $pattern');
    }
  }
}
