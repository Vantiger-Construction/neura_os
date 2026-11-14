import 'package:flutter/material.dart';

import '../../screens/journal_prompt_screen.dart';
import '../mood/mood_checkin_screen.dart';
import '../mood/mood_history_screen.dart';
import '../human/accessibility_screen.dart';
import 'appointment_prep_screen.dart';
import 'guided_support_activity.dart';
import 'guided_support_screen.dart';
import 'human_support_screen.dart';
import 'wellbeing_session_screen.dart';
import 'support_suggestion_screen.dart';
import 'usability_feedback_screen.dart';
import 'support_page_shortcuts.dart';

enum WellbeingDestination {
  settle,
  smallStep,
  reachSomeone,
  urgentHelp,
  quietWriting,
  journal,
  checkIn,
  history,
  reminder,
  suggestions,
  appointment,
  accessibility,
  feedback
}

/// Navigation only: mounting this card never opens personal storage or a model.
class WellbeingHomeCard extends StatelessWidget {
  const WellbeingHomeCard({super.key, this.destinationBuilder});
  final Widget Function(WellbeingDestination)? destinationBuilder;

  Widget _destination(WellbeingDestination destination) =>
      destinationBuilder?.call(destination) ??
      switch (destination) {
        WellbeingDestination.settle => const GuidedSupportScreen(),
        WellbeingDestination.smallStep => const WellbeingSessionScreen(),
        WellbeingDestination.reachSomeone => const HumanSupportScreen(),
        WellbeingDestination.urgentHelp =>
          const HumanSupportScreen(urgentOnly: true),
        WellbeingDestination.quietWriting => const GuidedSupportScreen(
            initialActivity: GuidedSupportActivity.quietWriting),
        WellbeingDestination.journal => const JournalPromptScreen(),
        WellbeingDestination.checkIn => const MoodCheckInScreen(),
        WellbeingDestination.history => const MoodHistoryScreen(),
        WellbeingDestination.reminder =>
          const WellbeingSessionScreen(reminder: true),
        WellbeingDestination.suggestions => const SupportSuggestionScreen(),
        WellbeingDestination.appointment => const AppointmentPrepScreen(),
        WellbeingDestination.accessibility => const AccessibilityScreen(),
        WellbeingDestination.feedback => const UsabilityFeedbackScreen(),
      };

  void _open(BuildContext context, WellbeingDestination destination) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            SupportPageShortcuts(child: _destination(destination))));
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
                  WellbeingDestination.settle),
              _choice(
                  context,
                  'Help me take one step',
                  'Make a task smaller, take a break, or try five minutes.',
                  Icons.self_improvement,
                  WellbeingDestination.smallStep),
              _choice(
                  context,
                  'Help me reach someone',
                  'Draft a message, prepare for care, or find human support.',
                  Icons.people_outline,
                  WellbeingDestination.reachSomeone),
              TextButton.icon(
                onPressed: () =>
                    _open(context, WellbeingDestination.urgentHelp),
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
                      WellbeingDestination.quietWriting),
                  _link(
                      context,
                      'Open my private journal',
                      'Review entries and explicitly save to your local journal.',
                      WellbeingDestination.journal),
                  _link(
                      context,
                      'Optional check-in',
                      'Record mood, with optional energy, sleep and a note.',
                      WellbeingDestination.checkIn),
                  _link(
                      context,
                      'My check-in history',
                      'A factual summary of what you chose to record.',
                      WellbeingDestination.history),
                  _link(
                      context,
                      'Gentle routine reminder',
                      'A silent reminder while this screen stays open.',
                      WellbeingDestination.reminder),
                  _link(
                      context,
                      'My suggestion choices',
                      'Choose when and which guided activities may be suggested.',
                      WellbeingDestination.suggestions),
                  _link(
                      context,
                      'Prepare for an appointment',
                      'Select check-ins and questions, then review your own summary.',
                      WellbeingDestination.appointment),
                  _link(
                      context,
                      'Comfort and accessibility',
                      'Text size, contrast, motion and visual comfort.',
                      WellbeingDestination.accessibility),
                  _link(
                      context,
                      'Help improve Neura',
                      'Optional usability feedback; nothing is sent automatically.',
                      WellbeingDestination.feedback),
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
          IconData icon, WellbeingDestination page) =>
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

  Widget _link(BuildContext context, String title, String detail,
          WellbeingDestination page) =>
      ListTile(
        title: Text(title),
        subtitle: Text(detail),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(context, page),
      );
}
