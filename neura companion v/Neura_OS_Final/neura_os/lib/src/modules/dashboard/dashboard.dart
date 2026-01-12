import 'package:flutter/material.dart';

import '../../shell/portal_route.dart';
import '../../shell/rooms_map_screen.dart';
import '../../shell/shell_prefs.dart';
import '../../../modules/diagnostics/diagnostics_screen.dart';
import '../../../modules/mood/mood_checkin_screen.dart';
import '../../../screens/dream_visualizer_screen.dart';
import '../../../screens/journal_prompt_screen.dart';
import '../focus/focus_office_screen.dart';
import '../legacy/legacy_home_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            _Tile(
              icon: Icons.dashboard_customize_outlined,
              title: 'Rooms Map',
              subtitle: 'Fast travel',
              onTap: () {
                final prefs = ShellPrefsController.instance.prefs.value;
                PortalNav.push(context, const RoomsMapScreen(), enabled: prefs.portalFx);
              },
            ),
            _Tile(
              icon: Icons.psychology_alt_outlined,
              title: 'Focus Office',
              subtitle: 'Set the vibe',
              onTap: () {
                final prefs = ShellPrefsController.instance.prefs.value;
                PortalNav.push(context, const FocusOfficeScreen(), enabled: prefs.portalFx);
              },
            ),
            _Tile(
              icon: Icons.auto_stories,
              title: 'Legacy Vault',
              subtitle: 'Time capsules',
              onTap: () {
                final prefs = ShellPrefsController.instance.prefs.value;
                PortalNav.push(context, const LegacyHomeScreen(), enabled: prefs.portalFx);
              },
            ),
            _Tile(
              icon: Icons.edit_note,
              title: 'Journal',
              subtitle: 'Prompt + entry',
              onTap: () {
                final prefs = ShellPrefsController.instance.prefs.value;
                PortalNav.push(context, const JournalPromptScreen(), enabled: prefs.portalFx);
              },
            ),
            _Tile(
              icon: Icons.favorite_border,
              title: 'Check‑In',
              subtitle: 'Mood snapshot',
              onTap: () {
                final prefs = ShellPrefsController.instance.prefs.value;
                PortalNav.push(context, const MoodCheckInScreen(), enabled: prefs.portalFx);
              },
            ),
            _Tile(
              icon: Icons.auto_awesome,
              title: 'Dreams',
              subtitle: 'Visualizer',
              onTap: () {
                final prefs = ShellPrefsController.instance.prefs.value;
                PortalNav.push(context, const DreamVisualizerScreen(), enabled: prefs.portalFx);
              },
            ),
            _Tile(
              icon: Icons.bug_report_outlined,
              title: 'Diagnostics',
              subtitle: 'Logs + self‑heal',
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

  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap});

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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28),
              const Spacer(),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
