import 'package:flutter/material.dart';

/// Starter community forum screen.
/// In a real build, this would connect to a moderated backend.
class CommunityForumScreen extends StatelessWidget {
  const CommunityForumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Community')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Community features are coming soon.\n\n'
            'Neura will connect you with others on similar journeys '
            'once a safe, moderated space is ready.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
