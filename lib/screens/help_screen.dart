import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Getting Started'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: const [
            Text('Welcome to Neura Companion!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Text('1. Log in or create an account to get started.'),
            Text('2. Record and track your daily rituals in Analytics.'),
            Text('3. Join community challenges and share posts.'),
            Text('4. Journal Your thoughts by text or voice.'),
            Text('5. Record and interpret your dreams at Dream Journal.'),
            Text('6. Customize your AI companion avatar in Settings.'),
            Text('7. Sync your data offline and back online seamlessly.'),
            Text('8. Manage subscriptions in the Profile tab.'),
            SizedBox(height: 20),
            Text('Enjoy your journey to better habits and wellness with Neura & Neuro!', style: TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}
