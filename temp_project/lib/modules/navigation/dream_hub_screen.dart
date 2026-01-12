import 'package:flutter/material.dart';

import '../../screens/dream_visualizer_screen.dart';
import '../../screens/dream_journal_calendar_screen.dart';
import '../../screens/dream_show_screen.dart';

class DreamHubScreen extends StatelessWidget {
  const DreamHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dreams')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Dream Visualizer'),
              subtitle: const Text('Timeline of dream scenes (hook AI image gen later).'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DreamVisualizerScreen())),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text('Dream Calendar'),
              subtitle: const Text('Browse dreams by date.'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DreamJournalCalendarScreen())),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.movie_outlined),
              title: const Text('Monthly Dream Show'),
              subtitle: const Text('Compile the month into a mini animated recap.'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DreamShowScreen())),
            ),
          ),
        ],
      ),
    );
  }
}
