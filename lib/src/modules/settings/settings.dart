import 'package:flutter/material.dart';

import '../../../config/supabase_config.dart';
import '../../../modules/coach/coach_settings_screen.dart';
import '../../../modules/human/accessibility_screen.dart';
import '../../../modules/human/life_snapshot_screen.dart';
import '../../../modules/human/persona_lab_screen.dart';
import '../../../modules/human/theme_screen.dart';
import '../../../persona/screens/agent_persona_settings_screen.dart';
import '../../../persona/screens/audience_settings_screen.dart';
import '../../../screens/avatar_selector_screen.dart';
import '../../../screens/ai_provider_settings_screen.dart';
import '../../../neura_link/neura_console_page.dart';
import '../../../screens/help_screen.dart';
import '../../../screens/neura_voice_settings_screen.dart';
import '../../../screens/profile_screen.dart';
import '../../../screens/subscription_screen.dart';
import '../../../screens/sync_status_screen.dart';
import '../../../screens/local_api_screen.dart';
import '../../shell/shell_prefs.dart';
import '../focus/focus_office_screen.dart';
import '../legacy/legacy_home_screen.dart';
import '../privacy/privacy_home_screen.dart';
import '../voice/voice_lab_screen.dart';
import '../../../modules/memory/memory_screen.dart';
import '../../../modules/feedback/feedback_screen.dart';
import '../../../intelligence/intelligence_center_screen.dart';
import '../../../notifications/notifications_settings_screen.dart';
import '../../../reliability/safe_boot.dart';

@visibleForTesting
bool cloudSettingsRoutesAllowed({
  required bool configured,
  required bool safeMode,
}) =>
    configured && !safeMode;

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
            leading: const Icon(Icons.api),
            title: const Text('Local app API'),
            subtitle: const Text(
                'Connect trusted apps with approval for each action'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const LocalApiScreen(),
            )),
          ),
          if (SupabaseConfig.isConfigured)
            AnimatedBuilder(
              animation: Listenable.merge([
                SafeBoot.instance.safeMode,
                SafeBoot.instance.restartRequired,
              ]),
              builder: (context, _) {
                final safeMode = SafeBoot.instance.safeMode.value;
                final restartRequired = SafeBoot.instance.restartRequired.value;
                if (!cloudSettingsRoutesAllowed(
                  configured: SupabaseConfig.isConfigured,
                  safeMode: safeMode,
                )) {
                  return Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.cloud_off_outlined),
                        title: const Text('Cloud account and sync paused'),
                        subtitle: Text(
                          restartRequired
                              ? 'Safe Mode remains active in this process. '
                                  'Restart Neura to restore Profile and Sync.'
                              : 'Safe Mode keeps Supabase offline. Clear Safe '
                                  'Mode in Diagnostics, then restart Neura to '
                                  'restore Profile and Sync.',
                        ),
                      ),
                      const Divider(),
                    ],
                  );
                }

                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.account_circle_outlined),
                      title: const Text('Profile & Account'),
                      subtitle:
                          const Text('Display name, email, and sign out.'),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ProfileScreen(),
                          ),
                        );
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.sync_outlined),
                      title: const Text('Sync Status'),
                      subtitle: const Text(
                        'Push and pull your journal entries manually.',
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SyncStatusScreen(),
                          ),
                        );
                      },
                    ),
                    const Divider(),
                  ],
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('AI Provider'),
            subtitle: const Text(
                'Securely connect, replace, or remove the model key.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AiProviderSettingsScreen(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: const Text('Neura Intelligence'),
            subtitle: const Text(
              'Signal controls, quiet hours, capability approvals, and decision receipts.',
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NeuraIntelligenceCenterScreen(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: const Text('Local Brain Console'),
            subtitle: const Text(
                'Streaming link, tone, connection health, and diagnostics.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NeuraConsolePage(
                    brainUrl: 'ws://127.0.0.1:8787',
                  ),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Voice Lab'),
            subtitle: const Text('Test Neura voice + live mic visemes.'),
            onTap: () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VoiceLabScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.psychology_alt_outlined),
            title: const Text('Focus Office'),
            subtitle: const Text('Switch Deep Work / Reflection / Wind Down.'),
            onTap: () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FocusOfficeScreen()));
            },
          ),
          const Divider(),
          _ShellToggles(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Privacy & Safety'),
            subtitle: const Text(
                'Data, backups, and what Neura does (and doesn\'t) do.'),
            onTap: () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrivacyHomeScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.psychology_outlined),
            title: const Text('What Neura Remembers'),
            subtitle: const Text(
                'View, search, or clear memory from past conversations.'),
            onTap: () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MemoryScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.auto_stories),
            title: const Text('Legacy Vault'),
            subtitle: const Text(
                'Time capsules, messages, and "future-you" archives.'),
            onTap: () {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LegacyHomeScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Themes & Avatars'),
            subtitle:
                const Text('Appearance, theme mode, and your Neura avatar.'),
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
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text("Neura's Voice"),
            subtitle: const Text('Pick which system voice Neura speaks with.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const NeuraVoiceSettingsScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.psychology_alt_outlined),
            title: const Text('Neura Coach'),
            subtitle: const Text(
                'Enable reflections, and browse your Coach Timeline.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CoachSettingsScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text("Neura's Personas"),
            subtitle: const Text(
                'Which specialist answers, and shared tone — warmth, humor, depth.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const AgentPersonaSettingsScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('Goals & Values'),
            subtitle: const Text(
                'What you want more of, and what you refuse to betray.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PersonaLabScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Audience Settings'),
            subtitle: const Text(
                'Choose who Neura is talking to, for safer tone and depth.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const AudienceSettingsScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.accessibility_new_outlined),
            title: const Text('Accessibility'),
            subtitle: const Text(
                'Motion, contrast, and text-size controls, plus Safe Mode.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccessibilityScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bar_chart_outlined),
            title: const Text('Life Snapshot'),
            subtitle: const Text(
                'A quick on-device snapshot of your mood and habits.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LifeSnapshotScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('Premium'),
            subtitle:
                const Text('Unlock Neura Premium with a one-time purchase.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text(
                'Weekly review, Legacy check-ins, and a daily mood nudge.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const NotificationsSettingsScreen()),
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('Send Feedback'),
            subtitle:
                const Text('Report a bug or tell us what\'s on your mind.'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FeedbackScreen()),
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
              child: Text('Neura OS Shell',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            SwitchListTile(
              value: prefs.ambientFx,
              onChanged: (v) => ShellPrefsController.instance
                  .update(prefs.copyWith(ambientFx: v)),
              title: const Text('Ambient FX'),
              subtitle: const Text('Subtle moving glow in the background.'),
              secondary: const Icon(Icons.blur_circular_outlined),
            ),
            SwitchListTile(
              value: prefs.portalFx,
              onChanged: (v) => ShellPrefsController.instance
                  .update(prefs.copyWith(portalFx: v)),
              title: const Text('Portal Transitions'),
              subtitle: const Text('Soft teleport-style screen transitions.'),
              secondary: const Icon(Icons.blur_on_outlined),
            ),
            SwitchListTile(
              value: prefs.walkingShimmer,
              onChanged: (v) => ShellPrefsController.instance
                  .update(prefs.copyWith(walkingShimmer: v)),
              title: const Text('Walking Path Shimmer'),
              subtitle:
                  const Text('A tiny animated "path" accent in the Rooms Map.'),
              secondary: const Icon(Icons.linear_scale_outlined),
            ),
          ],
        );
      },
    );
  }
}
