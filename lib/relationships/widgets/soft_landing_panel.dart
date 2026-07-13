
import 'package:flutter/material.dart';
import '../services/distress_detector.dart';

class SoftLandingPanel extends StatelessWidget {
  final DistressSignal signal;

  const SoftLandingPanel({super.key, required this.signal});

  @override
  Widget build(BuildContext context) {
    if (!signal.active) return const SizedBox.shrink();

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Soft landing mode',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text('Let’s keep this simple and gentle. One step at a time.'),
            const SizedBox(height: 8),
            if (signal.reasons.isNotEmpty) ...[
              const Text(
                'Why I\'m switching gears:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              ...signal.reasons.map(
                (r) => Text('• $r', style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () {
                    // Route to a 2-minute grounding ritual
                  },
                  child: const Text('Ground me for 2 minutes'),
                ),
                OutlinedButton(
                  onPressed: () {
                    // Route to a tiny "1-hour plan" screen
                  },
                  child: const Text('Plan just the next hour'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
