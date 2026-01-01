import 'package:flutter/material.dart';

import '../chat/neura_chat_screen.dart';
import '../diagnostics/diagnostics_screen.dart';

import '../../src/modules/legacy/legacy_home_screen.dart';
import '../../src/modules/settings/settings.dart';

import '../../screens/journal_prompt_screen.dart';
import '../../screens/dream_visualizer_screen.dart';
import '../../screens/dream_journal_calendar_screen.dart';

class NeuraDashboardScreen extends StatelessWidget {
  const NeuraDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tiles = <_TileData>[
      _TileData('Neura Chat', Icons.chat_bubble_outline, () => _push(context, const NeuraChatScreen())),
      _TileData('Journal Prompt', Icons.edit_note, () => _push(context, JournalPromptScreen())),
      _TileData('Dream Visualizer', Icons.auto_awesome, () => _push(context, DreamVisualizerScreen())),
      _TileData('Dream Calendar', Icons.calendar_month, () => _push(context, DreamJournalCalendarScreen())),
      _TileData('Legacy Vault', Icons.auto_stories, () => _push(context, const LegacyHomeScreen())),
      _TileData('Settings', Icons.settings, () => _push(context, const SettingsScreen())),
      _TileData('Diagnostics', Icons.monitor_heart_outlined, () => _push(context, const DiagnosticsScreen())),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neura OS'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.1,
          children: [
            for (final t in tiles)
              Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: t.onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(t.icon, size: 38),
                        const SizedBox(height: 10),
                        Text(t.title, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _TileData {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  const _TileData(this.title, this.icon, this.onTap);
}
