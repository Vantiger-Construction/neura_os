import 'package:flutter/material.dart';

import '../services/kids_game_library_service.dart';

class KidsModeHomeScreen extends StatefulWidget {
  const KidsModeHomeScreen({Key? key}) : super(key: key);

  @override
  State<KidsModeHomeScreen> createState() => _KidsModeHomeScreenState();
}

class _KidsModeHomeScreenState extends State<KidsModeHomeScreen> {
  final _games = KidsGameLibraryService.instance;

  bool _kidLock = true;

  @override
  Widget build(BuildContext context) {
    final games = _games.games;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neura Kids Mode'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.child_care),
                const SizedBox(width: 8),
                const Text(
                  'Parent Controls',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(_kidLock ? 'Kids locked' : 'Edit mode'),
                Switch(
                  value: !_kidLock,
                  onChanged: (v) {
                    setState(() {
                      _kidLock = !v;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Kids Mode is for gentle, age-appropriate interactions.
'
              'Neura avoids heavy topics, hard language, and adult content here.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            const Text(
              'Games & Activities',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (games.isEmpty)
              const Text('No games configured yet.'),
            if (games.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: games.length,
                  itemBuilder: (ctx, i) {
                    final name = games[i];
                    return Card(
                      child: ListTile(
                        title: Text(name),
                        subtitle: const Text('Tap to open (if supported).'),
                        trailing: const Icon(Icons.play_arrow),
                        onTap: () async {
                          final ok = await _games.launchGame(name);
                          if (!mounted) return;
                          if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Game launch is not wired yet for this platform.',
                                ),
                              ),
                            );
                          } else {
                            // In a real build, route to internal mini-games
                            // based on neura:// URL extracted in KidsGameLibraryService.
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Note: Parents should still supervise device use. Neura Kids Mode '
              'does not replace parental guidance.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
