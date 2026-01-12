import 'package:flutter/material.dart';

import '../integrations/neura_sources_hooks.dart';
import 'avatar_selector_screen.dart';
import 'dual_chat_screen.dart';
import 'dream_visualizer_screen.dart';
import 'voice_journal_screen.dart';
import 'profile_screen.dart';
import 'help_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Neura Companion'),
        actions: [
          IconButton(
            tooltip: 'Help',
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Your OS for becoming a better human — with a friendly android in the corner quietly judging your habits (lovingly).',
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickChip(
                label: 'Blink',
                onTap: NeuraSourcesHooks.pulseBlink,
              ),
              _QuickChip(
                label: 'Wave',
                onTap: NeuraSourcesHooks.pulseWave,
              ),
              _QuickChip(
                label: 'Listening',
                onTap: () {
                  NeuraSourcesHooks.sttStart();
                  Future.delayed(const Duration(seconds: 2), NeuraSourcesHooks.sttStop);
                },
              ),
              _QuickChip(
                label: 'Talking',
                onTap: () {
                  NeuraSourcesHooks.ttsStart();
                  Future.delayed(const Duration(seconds: 2), NeuraSourcesHooks.ttsStop);
                },
              ),
              _QuickChip(
                label: 'Thinking',
                onTap: () {
                  NeuraSourcesHooks.thinkingStart();
                  Future.delayed(const Duration(seconds: 2), NeuraSourcesHooks.thinkingStop);
                },
              ),
              _QuickChip(
                label: 'Mood +',
                onTap: () => NeuraSourcesHooks.setMood(mood: 0.8, energy: 0.75),
              ),
              _QuickChip(
                label: 'Mood -',
                onTap: () => NeuraSourcesHooks.setMood(mood: 0.2, energy: 0.35),
              ),
            ],
          ),

          const SizedBox(height: 20),

          const Text('Modules', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          _ModuleTile(
            icon: Icons.chat_bubble_outline,
            title: 'Dual Chat',
            subtitle: 'Talk with Neura / Neuro and watch the avatar react.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DualChatScreen()),
            ),
          ),
          _ModuleTile(
            icon: Icons.face_retouching_natural,
            title: 'Avatar Selector',
            subtitle: 'Swap between Rive / Lottie / Sprite avatars (safe fallbacks).',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AvatarSelectorScreen()),
            ),
          ),
          _ModuleTile(
            icon: Icons.spatial_tracking,
            title: 'Dream Visualizer',
            subtitle: 'A starter screen for your dream scene engine.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DreamVisualizerScreen()),
            ),
          ),
          _ModuleTile(
            icon: Icons.mic_none,
            title: 'Voice Journal',
            subtitle: 'Record voice notes + (optional) STT hooks.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VoiceJournalScreen()),
            ),
          ),
          _ModuleTile(
            icon: Icons.person_outline,
            title: 'Profile',
            subtitle: 'User profile + future personalization controls.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ProfileScreen()),
            ),
          ),

          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),

          _ModuleTile(
            icon: Icons.bug_report_outlined,
            title: 'Test Error Vault',
            subtitle: 'Triggers a handled exception so Dimensional Sync can log it.',
            onTap: () {
              // This will be captured by NeuraFaultSystem + NeuraDiagnostics hooks (see main.dart).
              NeuraSourcesHooks.error(StateError('Dimensional Sync test error (safe to ignore).'), StackTrace.current, 'dimensional_sync_test');
            },
          ),
        ],
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModuleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(label: Text(label), onPressed: onTap);
  }
}
