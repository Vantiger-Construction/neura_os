import 'package:flutter/material.dart';

import '../../../../modules/coach/coach_settings_screen.dart';
import '../../../../modules/human/theme_screen.dart';
import '../../../../screens/avatar_selector_screen.dart';
import '../../../../screens/help_screen.dart';
import '../../shell/portal_route.dart';
import '../../shell/rooms_map_screen.dart';
import '../../shell/shell_prefs.dart';
import '../focus/focus_office_screen.dart';
import '../legacy/legacy_home_screen.dart';
import '../privacy/privacy_home_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ListTile(
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: const Text('Rooms Map'),
            subtitle: const Text('Quick-launch any module with portal transitions.'),
            onTap: () {
              PortalNav.push(context, const RoomsMapScreen(), enabled: true);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.psychology_alt_outlined),
            title: const Text('Focus Office'),
            subtitle: const Text('Switch Deep Work / Reflection / Wind Down.'),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FocusOfficeScreen()));
            },
          ),
          const Divider(),
          _ShellToggles(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Privacy & Safety'),
            subtitle: const Text('Data, backups, and what Neura does (and doesn\'t) do.'),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyHomeScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.auto_stories),
            title: const Text('Legacy Vault'),
            subtitle: const Text('Time capsules, messages, and “future-you” archives.'),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LegacyHomeScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Themes & Avatars'),
            subtitle: const Text('Appearance, theme mode, and your Neura avatar.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ThemeScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Choose Avatar'),
            subtitle: const Text('Pick which Neura companion represents you.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AvatarSelectorScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.psychology_alt_outlined),
            title: const Text('Neura Coach'),
            subtitle: const Text('Enable reflections, and browse your Coach Timeline.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CoachSettingsScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help'),
            subtitle: const Text('Getting started, tips, and troubleshooting.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HelpScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ShellToggles extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ShellPrefsController.instance.prefs,
      builder: (context, prefs, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Neura OS Shell', style: Theme.of(context).textTheme.titleMedium),
            ),
            SwitchListTile(
              value: prefs.ambientFx,
              onChanged: (v) => ShellPrefsController.instance.update(prefs.copyWith(ambientFx: v)),
              title: const Text('Ambient FX'),
              subtitle: const Text('Subtle moving glow in the background.'),
              secondary: const Icon(Icons.blur_circular_outlined),
            ),
            SwitchListTile(
              value: prefs.portalFx,
              onChanged: (v) => ShellPrefsController.instance.update(prefs.copyWith(portalFx: v)),
              title: const Text('Portal Transitions'),
              subtitle: const Text('Soft teleport-style screen transitions.'),
              secondary: const Icon(Icons.blur_on_outlined),
            ),
            SwitchListTile(
              value: prefs.walkingShimmer,
              onChanged: (v) => ShellPrefsController.instance.update(prefs.copyWith(walkingShimmer: v)),
              title: const Text('Walking Path Shimmer'),
              subtitle: const Text('A tiny animated “path” accent in the Rooms Map.'),
              secondary: const Icon(Icons.linear_scale_outlined),
            ),
          ],
        );
      },
    );
  }
}
