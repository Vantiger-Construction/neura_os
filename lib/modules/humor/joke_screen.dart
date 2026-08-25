import 'package:flutter/material.dart';

import '../../services/neura_tts_service.dart';
import 'joke_prefs_controller.dart';
import 'neura_joke_engine.dart';

class JokeScreen extends StatefulWidget {
  const JokeScreen({super.key});

  @override
  State<JokeScreen> createState() => _JokeScreenState();
}

class _JokeScreenState extends State<JokeScreen> {
  String? _current;
  bool _speaking = false;

  Future<void> _tellJoke() async {
    final prefs = JokePrefsController.instance;
    final exclude = {...prefs.dislikes.value, if (_current != null) _current!};
    final joke = NeuraJokeEngine.randomJoke(
      includeSpicy: prefs.includeSpicy.value,
      exclude: exclude,
    );
    setState(() {
      _current = joke;
      _speaking = true;
    });
    try {
      await NeuraTtsService.instance.speak(joke);
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = JokePrefsController.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Neura Jokes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.mood, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    _current ?? 'Need a laugh? Tap below.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _speaking ? null : _tellJoke,
                    icon: const Icon(Icons.mood),
                    label: Text(
                        _current == null ? 'Tell me a joke' : 'Another one'),
                  ),
                  if (_current != null) ...[
                    const SizedBox(height: 12),
                    ValueListenableBuilder<List<String>>(
                      valueListenable: prefs.favorites,
                      builder: (context, favorites, _) {
                        final isFav = favorites.contains(_current);
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: isFav
                                  ? 'Remove from favorites'
                                  : 'Save to favorites',
                              onPressed: () => prefs.toggleFavorite(_current!),
                              icon: Icon(
                                isFav ? Icons.favorite : Icons.favorite_border,
                                color: Colors.pinkAccent,
                              ),
                            ),
                            IconButton(
                              tooltip: "Don't tell this one again",
                              onPressed: () async {
                                await prefs.addDislike(_current!);
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          "Got it, won't repeat that one.")),
                                );
                              },
                              icon: const Icon(Icons.thumb_down_outlined),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<bool>(
            valueListenable: prefs.includeSpicy,
            builder: (context, includeSpicy, _) {
              return SwitchListTile(
                value: includeSpicy,
                onChanged: (v) => prefs.setIncludeSpicy(v),
                title: const Text('Include spicier jokes'),
                subtitle: const Text('A little edgier, still nothing crude.'),
                secondary: const Icon(Icons.local_fire_department_outlined),
              );
            },
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<List<String>>(
            valueListenable: prefs.favorites,
            builder: (context, favorites, _) {
              if (favorites.isEmpty) return const SizedBox.shrink();
              return Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text('Favorites',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    for (final joke in favorites)
                      ListTile(
                        title: Text(joke),
                        trailing: IconButton(
                          icon: const Icon(Icons.favorite,
                              color: Colors.pinkAccent),
                          onPressed: () => prefs.toggleFavorite(joke),
                        ),
                        onTap: () => setState(() => _current = joke),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
