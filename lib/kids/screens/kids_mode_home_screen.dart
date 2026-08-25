import 'dart:async';

import 'package:flutter/material.dart';

import '../services/kids_game_library_service.dart';
import 'breathing_game_screen.dart';
import 'gratitude_stars_screen.dart';
import 'kids_neura_chat_screen.dart';

class KidsModeHomeScreen extends StatefulWidget {
  const KidsModeHomeScreen({super.key});

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
              'Kids Mode is for gentle, age-appropriate interactions.\n'
              'Neura avoids heavy topics, hard language, and adult content here.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            // Always available regardless of _kidLock -- that toggle guards
            // access to Parent Controls/edit mode, not core kid-safe
            // features. Chat's real safety gate is inside the screen itself
            // (forces the global audience to `child` for its lifetime).
            Card(
              child: ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Talk to Neura'),
                subtitle: const Text('A safe, kid-friendly chat.'),
                trailing: const Icon(Icons.play_arrow),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const KidsNeuraChatScreen()),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Games & Activities',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (games.isEmpty) const Text('No games configured yet.'),
            if (games.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: games.length,
                  itemBuilder: (ctx, i) {
                    final name = games[i];
                    return Card(
                      child: ListTile(
                        title: Text(name),
                        subtitle: const Text('Tap to open.'),
                        trailing: const Icon(Icons.play_arrow),
                        onTap: () async {
                          final ok = await _games.launchGame(name);
                          if (!ctx.mounted) return;
                          if (!ok) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Game launch is not supported on this platform yet.',
                                ),
                              ),
                            );
                          } else {
                            // Route internal neura:// mini-games.
                            final target = _games.getLaunchTarget(name);
                            if (!ctx.mounted) return;
                            if (target == 'neura://kids/breathing') {
                              unawaited(
                                  Navigator.of(ctx).push(MaterialPageRoute(
                                builder: (_) => const BreathingGameScreen(),
                              )));
                            } else if (target == 'neura://kids/gratitude') {
                              unawaited(
                                  Navigator.of(ctx).push(MaterialPageRoute(
                                builder: (_) => const GratitudeStarsScreen(),
                              )));
                            }
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
