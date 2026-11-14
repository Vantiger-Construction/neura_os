import 'package:flutter/material.dart';

import '../../screens/journal_prompt_screen.dart';
import '../mood/mood_checkin_screen.dart';
import '../mood/mood_history_screen.dart';
import 'guided_support_activity.dart';
import 'guided_support_screen.dart';
import 'human_support_screen.dart';
import 'wellbeing_session_screen.dart';

/// Navigation only: mounting this card never opens personal storage or a model.
class WellbeingHomeCard extends StatelessWidget {
  const WellbeingHomeCard({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('What would help right now?',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                  'Choose what fits. You can skip, stop, or come back later.'),
              const SizedBox(height: 16),
              _choice(
                  context,
                  'Help me settle',
                  'Grounding, optional gentle breathing, or a quiet pause.',
                  Icons.spa_outlined,
                  const GuidedSupportScreen()),
              _choice(
                  context,
                  'Help me take one step',
                  'Make a task smaller, take a break, or try five minutes.',
                  Icons.self_improvement,
                  const WellbeingSessionScreen()),
              _choice(
                  context,
                  'Help me reach someone',
                  'Draft a message, prepare for care, or find human support.',
                  Icons.people_outline,
                  const HumanSupportScreen()),
              TextButton.icon(
                onPressed: () =>
                    _open(context, const HumanSupportScreen(urgentOnly: true)),
                icon: const Icon(Icons.support_agent),
                label: const Text('Urgent help and crisis contacts'),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('More ways to care for yourself'),
                children: [
                  _link(
                      context,
                      'Write without saving',
                      'Optional prompts; writing clears when you leave.',
                      const GuidedSupportScreen(
                          initialActivity: GuidedSupportActivity.quietWriting)),
                  _link(
                      context,
                      'Open my private journal',
                      'Review entries and explicitly save to your local journal.',
                      const JournalPromptScreen()),
                  _link(
                      context,
                      'Optional check-in',
                      'Record mood, with optional energy, sleep and a note.',
                      const MoodCheckInScreen()),
                  _link(
                      context,
                      'My check-in history',
                      'A factual summary of what you chose to record.',
                      const MoodHistoryScreen()),
                  _link(
                      context,
                      'Gentle routine reminder',
                      'A silent reminder while this screen stays open.',
                      const WellbeingSessionScreen(reminder: true)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                  'Everyday support for adults. Neura does not diagnose, '
                  'provide emergency monitoring, or replace professional care.'),
            ],
          ),
        ),
      );

  Widget _choice(BuildContext context, String title, String detail,
          IconData icon, Widget page) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
          onPressed: () => _open(context, page),
          child: Row(children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(detail),
                ])),
          ]),
        ),
      );

  Widget _link(
          BuildContext context, String title, String detail, Widget page) =>
      ListTile(
        title: Text(title),
        subtitle: Text(detail),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(context, page),
      );
}
