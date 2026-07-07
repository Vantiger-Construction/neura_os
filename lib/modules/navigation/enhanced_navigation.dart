import 'package:flutter/material.dart';
import '../../neura_shell/neura_shell.dart';
import '../../neura_shell/models/neura_room.dart';


import '../../insights/screens/weekly_snapshot_screen.dart';
import '../../modules/mood/mood_checkin_screen.dart';
import '../../modules/mood/mood_history_screen.dart';
import '../../screens/dream_journal_calendar_screen.dart';
import '../../screens/dream_show_screen.dart';
import '../../screens/dream_visualizer_screen.dart';
import '../../screens/journal_prompt_screen.dart';
import '../../screens/voice_journal_screen.dart';
import '../../src/modules/legacy/legacy_home_screen.dart';
import '../../src/modules/settings/settings.dart';
import '../chat/neura_chat_screen.dart';
import '../diagnostics/diagnostics_screen.dart';

class EnhancedNavigation extends StatefulWidget {
  const EnhancedNavigation({super.key});

  @override
  State<EnhancedNavigation> createState() => _EnhancedNavigationState();
}

class _EnhancedNavigationState extends State<EnhancedNavigation> {
  int _index = 0;

  void _openChat() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NeuraChatScreen()));
  }

  void _openDiagnostics() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiagnosticsScreen()));
  }

  void _onTab(int i) {
    setState(() => _index = i);

    // Optional magic: sync rooms to tabs, so the OS "moves" with you.
    final shell = NeuraShell.of(context);
    if (!shell.isLoaded) return;
    if (shell.autoRoomSync) {
      shell.setRoom(_roomForIndex(i));
    }
  }

  NeuraRoom _roomForIndex(int i) {
    switch (i) {
      case 0:
        return NeuraRoom.penthouse;
      case 1:
        return NeuraRoom.reflectionBay;
      case 2:
        return NeuraRoom.dreamAtrium;
      case 3:
        return NeuraRoom.legacyVault;
      case 4:
        return NeuraRoom.moodDen;
      default:
        return NeuraRoom.penthouse;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _Dashboard(openChat: _openChat, openDiagnostics: _openDiagnostics),
      const _JournalHub(),
      const _DreamHub(),
      const LegacyHomeScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: pages)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openChat,
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('Neura'),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _onTab,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: 'Journal'),
          BottomNavigationBarItem(icon: Icon(Icons.nights_stay_outlined), label: 'Dreams'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_stories), label: 'Legacy'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final VoidCallback openChat;
  final VoidCallback openDiagnostics;

  const _Dashboard({required this.openChat, required this.openDiagnostics});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Neura OS', style: Theme.of(context).textTheme.headlineMedium),
            ),
            IconButton(onPressed: openDiagnostics, icon: const Icon(Icons.bug_report_outlined)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'An OS for becoming a better human. No capes required.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Tile(
              icon: Icons.chat_bubble_outline,
              title: 'Talk to Neura',
              subtitle: 'Plan, reflect, reset.',
              onTap: openChat,
            ),
            _Tile(
              icon: Icons.favorite_border,
              title: 'Mood Check‑In',
              subtitle: 'Track how you feel.',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoodCheckInScreen())),
            ),
            _Tile(
              icon: Icons.timeline,
              title: 'Mood History',
              subtitle: 'Your emotional weather.',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoodHistoryScreen())),
            ),
            _Tile(
              icon: Icons.insights,
              title: 'Weekly Snapshot',
              subtitle: 'Mood trend, rituals, and export.',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeeklySnapshotScreen())),
            ),
            _Tile(
              icon: Icons.edit_note,
              title: 'Journal Prompt',
              subtitle: 'Time-aware prompt.',
              onTap: () {
                final shell = NeuraShell.of(context);
                if (shell.isLoaded) shell.setRoom(NeuraRoom.reflectionBay);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => JournalPromptScreen()));
              },
            ),
            _Tile(
              icon: Icons.mic_none,
              title: 'Voice Journal',
              subtitle: 'Speak it. Save it.',
              onTap: () {
                final shell = NeuraShell.of(context);
                if (shell.isLoaded) shell.setRoom(NeuraRoom.reflectionBay);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VoiceJournalScreen()));
              },
            ),
            _Tile(
              icon: Icons.auto_awesome,
              title: 'Dream Visualizer',
              subtitle: 'Dream timeline.',
              onTap: () {
                final shell = NeuraShell.of(context);
                if (shell.isLoaded) shell.setRoom(NeuraRoom.dreamAtrium);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => DreamVisualizerScreen()));
              },
            ),
            _Tile(
              icon: Icons.auto_stories,
              title: 'Legacy Vault',
              subtitle: 'Messages for future-you.',
              onTap: () {
                final shell = NeuraShell.of(context);
                if (shell.isLoaded) shell.setRoom(NeuraRoom.legacyVault);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LegacyHomeScreen()));
              },
            ),
            _Tile(
              icon: Icons.settings_outlined,
              title: 'Settings',
              subtitle: 'Privacy, safety, controls.',
              onTap: () {
                final shell = NeuraShell.of(context);
                if (shell.isLoaded) shell.setRoom(NeuraRoom.moodDen);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
            ),
            _Tile(
              icon: Icons.bug_report_outlined,
              title: 'Diagnostics',
              subtitle: 'Logs + Dimensional Sync.',
              onTap: openDiagnostics,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('Daily tiny quest'),
            subtitle: const Text('Pick one: drink water • 10-min walk • write one honest paragraph'),
            trailing: const Icon(Icons.chevron_right),
            onTap: openChat,
          ),
        ),
      ],
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
    return SizedBox(
      width: 240,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon),
                const SizedBox(height: 10),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JournalHub extends StatelessWidget {
  const _JournalHub();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Journal')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Journal hub: prompts + voice journaling. Mood-aware prompts are next.'),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Get a prompt'),
              subtitle: const Text('Time-aware prompt (mood-aware next).'),
              onTap: () {
                final shell = NeuraShell.of(context);
                if (shell.isLoaded) shell.setRoom(NeuraRoom.reflectionBay);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => JournalPromptScreen()));
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.mic_none),
              title: const Text('Voice journal'),
              subtitle: const Text('Speech-to-text (device permitting).'),
              onTap: () {
                final shell = NeuraShell.of(context);
                if (shell.isLoaded) shell.setRoom(NeuraRoom.reflectionBay);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VoiceJournalScreen()));
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('Mood check‑in'),
              subtitle: const Text('Quick emotional snapshot.'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MoodCheckInScreen())),
            ),
          ),
        ],
      ),
    );
  }
}

class _DreamHub extends StatelessWidget {
  const _DreamHub();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dreams')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Dream hub: visualizer, calendar, and monthly “show” compilation.'),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Dream Visualizer'),
              subtitle: const Text('Timeline of dream scenes.'),
              onTap: () {
                final shell = NeuraShell.of(context);
                if (shell.isLoaded) shell.setRoom(NeuraRoom.dreamAtrium);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => DreamVisualizerScreen()));
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text('Dream Calendar'),
              subtitle: const Text('Browse dreams by date.'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DreamJournalCalendarScreen())),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.movie_filter_outlined),
              title: const Text('Monthly Dream Show'),
              subtitle: const Text('Auto-compiled highlight reel.'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DreamShowScreen())),
            ),
          ),
        ],
      ),
    );
  }
}
