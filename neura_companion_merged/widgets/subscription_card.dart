import 'package:flutter/material.dart';

class SubscriptionCard extends StatelessWidget {
  const SubscriptionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Premium Subscription'),
            const SizedBox(height: 8),
            const Text('Unlock all features'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // TODO: Implement subscription logic
              },
              child: const Text('Subscribe'),
            ),
          ],
        ),
      ),
    );
  }
}
