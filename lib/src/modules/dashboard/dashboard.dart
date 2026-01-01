import 'package:flutter/material.dart';

import '../../shell/portal_route.dart';
import '../../shell/rooms_map_screen.dart';
import '../../shell/shell_prefs.dart';
import '../../../modules/diagnostics/diagnostics_screen.dart';
import '../../../modules/mood/mood_checkin_screen.dart';
import '../../../screens/dream_visualizer_screen.dart';
import '../../../screens/journal_prompt_screen.dart';
import '../../../modules/pay_it_forward/pay_it_forward_screen.dart';
import '../../../modules/pay_it_forward/goodwill_controller.dart';
import '../../../modules/pay_it_forward/goodwill_widgets.dart';
import '../focus/focus_office_screen.dart';
import '../legacy/legacy_home_screen.dart';
import '../../../widgets/neura_explain.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Ensure Goodwill is ready so streak badge renders quickly.
    GoodwillController.instance.ensureLoaded();
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: GoodwillController.instance.streak,
              builder: (ctx, streak, _) {
                return _Tile(
                  icon: Icons.volunteer_activism,
                  title: 'Pay It Forward',
                  subtitle: streak > 0 ? 'Streak: $streak day${streak == 1 ? '' : 's'}' : 'Do one small good thing',
                  trailing: GoodwillStreakBadge(streak: streak, compact: true),
                  explain: const NeuraExplainSpec(
                    title: 'Pay It Forward',
                    body: 'A kindness loop designed to make Neura better for humans (including the one using the app).',
                    bullets: [
                      'Log small good actions and build a streak.',
                      'Streaks encourage — they don\'t judge.',
                      'Stored locally and deletable anytime.',
                    ],
                  ),
                  onTap: () {
                    final prefs = ShellPrefsController.instance.prefs.value;
                    PortalNav.push(context, const PayItForwardScreen(), enabled: prefs.portalFx);
                  },
                );
              },
            ),
            _Tile(
              icon: Icons.dashboard_customize_outlined,
              title: 'Rooms Map',
              subtitle: 'Fast travel',
              explain: const NeuraExplainSpec(
                title: 'Rooms Map',
                body: 'Neura OS is organized like a space you can move through. Rooms are modules.',
                bullets: [
                  'Fast travel instead of hunting menus.',
                  'Each room is a feature cluster (Journal, Dreams, Mood, etc.).',
                ],
              ),
              onTap: () {
                final prefs = ShellPrefsController.instance.prefs.value;
                PortalNav.push(context, const RoomsMapScreen(), enabled: prefs.portalFx);
              },
            ),
            _Tile(
              icon: Icons.psychology_alt_outlined,
              title: 'Focus Office',
              subtitle: 'Set the vibe',
              explain: const NeuraExplainSpec(
                title: 'Focus Office',
                body: 'A low-friction place to switch into focus mode without turning your brain into a task hamster.',
                bullets: [
                  'Reduces visual noise.',
                  'Helps you do the next best step.',
                ],
              ),
              onTap: () {
                final prefs = ShellPrefsController.instance.prefs.value;
                PortalNav.push(context, const FocusOfficeScreen(), enabled: prefs.portalFx);
              },
            ),
            _Tile(
              icon: Icons.auto_stories,
              title: 'Legacy Vault',
              subtitle: 'Time capsules',
              explain: const NeuraExplainSpec(
                title: 'Legacy Vault',
                body: 'A private place for messages, templates, and future-you insurance.',
                bullets: [
                  'Capture memories and intentions.',
                  'Exportable and guardable.',
                ],
              ),
              onTap: () {
                final prefs = ShellPrefsController.instance.prefs.value;
                PortalNav.push(context, const LegacyHomeScreen(), enabled: prefs.portalFx);
              },
            ),
            _Tile(
              icon: Icons.edit_note,
              title: 'Journal',
              subtitle: 'Prompt + entry',
              explain: const NeuraExplainSpec(
                title: 'Journal',
                body: 'Journaling isn\'t about being poetic. It\'s about getting the truth out of your skull and onto paper.',
                bullets: [
                  'Prompts reduce blank-page paralysis.',
                  'Entries can be exported or deleted.',
                ],
              ),
              onTap: () {
                final prefs = ShellPrefsController.instance.prefs.value;
                PortalNav.push(context, const JournalPromptScreen(), enabled: prefs.portalFx);
              },
            ),
            _Tile(
              icon: Icons.favorite_border,
              title: 'Check‑In',
              subtitle: 'Mood snapshot',
              explain: const NeuraExplainSpec(
                title: 'Mood Check‑In',
                body: 'Quick check-ins build a map of what affects you (sleep, stress, routines) without making you do spreadsheets.',
                bullets: [
                  'Used for trends and gentle suggestions.',
                  'Stored locally unless you enable sync.',
                ],
              ),
              onTap: () {
                final prefs = ShellPrefsController.instance.prefs.value;
                PortalNav.push(context, const MoodCheckInScreen(), enabled: prefs.portalFx);
              },
            ),
            _Tile(
              icon: Icons.auto_awesome,
              title: 'Dreams',
              subtitle: 'Visualizer',
              explain: const NeuraExplainSpec(
                title: 'Dream Visualizer',
                body: 'Dreams are the brain doing weird housekeeping. This module helps you log and reflect on patterns.',
                bullets: [
                  'Record dreams (text/voice).',
                  'View patterns over time.',
                ],
              ),
              onTap: () {
                final prefs = ShellPrefsController.instance.prefs.value;
                PortalNav.push(context, const DreamVisualizerScreen(), enabled: prefs.portalFx);
              },
            ),
            _Tile(
              icon: Icons.bug_report_outlined,
              title: 'Diagnostics',
              subtitle: 'Logs + self‑heal',
              explain: const NeuraExplainSpec(
                title: 'Diagnostics',
                body: 'Because software should fail gracefully — with receipts and a sense of humor.',
                bullets: [
                  'View logs.',
                  'Run self-heal routines.',
                ],
              ),
              onTap: () {
                final prefs = ShellPrefsController.instance.prefs.value;
                PortalNav.push(context, const DiagnosticsScreen(), enabled: prefs.portalFx);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final NeuraExplainSpec? explain;
  final Widget? trailing;

  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.explain,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(0.06),
          border: Border.all(color: Colors.white12),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 28),
                      const Spacer(),
                      if (trailing != null) trailing!,
                    ],
                  ),
                  const Spacer(),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (explain != null)
              Positioned(
                right: 6,
                top: 6,
                child: IconButton(
                  tooltip: 'Why is this here?',
                  icon: const Icon(Icons.help_outline),
                  onPressed: () => showNeuraExplain(context, spec: explain!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
