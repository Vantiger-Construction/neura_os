import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Getting Started')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(
              header: true,
              child: Text(
                'Welcome to Neura Companion!',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Take your time. Start with a few words or a small check-in. '
              'Local journaling, mood check-ins and guided reflection do not '
              'require an account.',
            ),
            const SizedBox(height: 24),
            const _HelpSection(
              title: 'Find your way',
              guidance: 'On Home, tap Ask Neura or type a command… and search '
                  'in Find a room or action for the screen names below. '
                  'Controls opens Settings.',
            ),
            const _HelpSection(
              title: 'Write a local journal',
              guidance: 'Open Journal Prompt, type under Write a response, '
                  'then tap Save response. Wait for Saved to your local '
                  'journal. Reopen an entry from Saved responses. '
                  'Text journaling works offline on this device.',
            ),
            const _HelpSection(
              title: 'Record your own mood',
              guidance: 'Open Mood Check-In, choose your own rating from 0 to '
                  '10, add an optional note and tap Save check-in. Open Mood '
                  'History to review the ratings and notes you entered.',
            ),
            const _HelpSection(
              title: 'Try guided reflection',
              guidance: 'Open Support Center and tap Help me through this. '
                  'Choose Quiet writing, Grounding pause or One small plan. '
                  'These are fixed, optional reflection activities; you can '
                  'stop whenever you like. Writing here is temporary and '
                  'clears when you finish or leave the activity. Use Journal '
                  'Prompt for words you want to save. For health concerns, '
                  'seek a qualified professional.',
            ),
            const _HelpSection(
              title: "Visit Neura's spaces",
              guidance: 'Open Spaces and choose a room card, such as '
                  'Reflection Bay or Care Wing, to visit its activities. '
                  'To change the background room, press and hold the app '
                  'background, then tap a room in Choose a room.',
            ),
            const _HelpSection(
              title: 'Voice journaling (optional)',
              guidance: 'Voice Journal needs microphone access and a working '
                  'device speech service. Windows uses Windows speech '
                  'recognition; phones use their platform speech service. '
                  'Voice services may need an internet connection. Tap Start '
                  'listening, then Stop listening, review the words and tap '
                  'Save transcript. If speech is unavailable, use Journal '
                  'Prompt. Safe Mode keeps the microphone off.',
            ),
            const _HelpSection(
              title: 'Conversation choices',
              guidance: 'Open Talk to Neura for text chat. Cloud replies need '
                  'internet access, a provider key in Controls > AI Provider '
                  'and your approval for each request. Read the request '
                  'preview before approving.\n\n'
                  'Offline Ollama requires a Windows build with Neura\'s '
                  'local engine, Ollama running on this PC and the downloaded '
                  'qwen3:4b-instruct model. It also requires at least 7 GiB '
                  'total RAM and 3.5 GiB available. Choose Offline Ollama '
                  'from the chat\'s computer/cloud menu for typed text. '
                  'The model can make mistakes.',
            ),
            const _HelpSection(
              title: 'Privacy and local data',
              guidance: 'Controls > Privacy & Safety > Data Controls offers '
                  'Legacy Vault import/export and local deletion controls. '
                  'Decrypted Legacy Vault exports require the capsules\' '
                  'passphrase. Read the confirmation before deleting. After '
                  'a full wipe attempt, read the result and restart Neura '
                  'before continuing. Copies already shared outside Neura '
                  'are unaffected. Device lock requires supported device '
                  'authentication.\n\n'
                  'Local journal and mood entries are stored on this device. '
                  'Keep important copies yourself while cross-device sync '
                  'is still being verified.',
            ),
            const Text(
              'One small step is enough. Explore at your own pace with Neura.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({required this.title, required this.guidance});

  final String title;
  final String guidance;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Text(guidance),
        ],
      ),
    );
  }
}
