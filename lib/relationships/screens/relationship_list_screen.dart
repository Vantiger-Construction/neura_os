
import 'package:flutter/material.dart';
import '../services/relationship_profile_service.dart';
import '../services/promise_service.dart';
import '../services/distress_detector.dart';
import '../models/relationship_profile.dart';
import '../models/relationship_suggestion.dart';
import '../widgets/promises_summary_tile.dart';
import '../widgets/one_good_move_tile.dart';
import '../widgets/soft_landing_panel.dart';
import '../../modules/mood/mood_store.dart';
import 'promises_list_screen.dart';
import 'relationship_detail_screen.dart';

class RelationshipListScreen extends StatefulWidget {
  const RelationshipListScreen({super.key});

  @override
  State<RelationshipListScreen> createState() =>
      _RelationshipListScreenState();
}

class _RelationshipListScreenState extends State<RelationshipListScreen> {
  List<RelationshipProfile> _profiles = [];
  bool _loading = true;
  bool _promisesOutstanding = false;
  List<int> _recentMoods = [];
  int? _daysSinceLastContact;
  DistressSignal _distressSignal = DistressSignal(active: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await RelationshipProfileService.instance.refreshOpenPromiseCounts();
    final list = await RelationshipProfileService.instance.all();

    final openCount = await PromiseService.instance.openCount();

    final moodEntries = await MoodStore.instance.getAll();
    final recentEntries = moodEntries.length > 10
        ? moodEntries.sublist(moodEntries.length - 10)
        : moodEntries;
    final recentMoods = recentEntries
        .map((e) => ((e.mood0to10 - 5) / 2.5).round().clamp(-2, 2))
        .toList();

    int? daysSinceLastContact;
    for (final p in list) {
      final lastContact = p.lastContact;
      if (lastContact == null) continue;
      final days = DateTime.now().difference(lastContact).inDays;
      if (daysSinceLastContact == null || days > daysSinceLastContact) {
        daysSinceLastContact = days;
      }
    }

    final signal = DistressDetector().detect(
      recentMoods: recentMoods,
      appOpensLastHour: 0,
      lotsOfNegativeWords: false,
    );

    if (!mounted) return;
    setState(() {
      _profiles = list;
      _promisesOutstanding = openCount > 0;
      _recentMoods = recentMoods;
      _daysSinceLastContact = daysSinceLastContact;
      _distressSignal = signal;
      _loading = false;
    });
  }

  Future<void> _addProfile() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New person/client'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await RelationshipProfileService.instance.create(name);
    await _load();
  }

  /// The tile's suggestions aren't tagged with a type, only a title/label --
  /// route by title. "Follow-through time" is the one promise-specific
  /// suggestion; everything else is some flavor of "reach out to someone",
  /// and this app has no messaging feature, so the honest destination is
  /// picking who it's about and opening their profile.
  void _handleOneGoodMoveAction(RelationshipSuggestion suggestion) {
    if (suggestion.title == 'Follow-through time') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PromisesListScreen()),
      ).then((_) => _load());
      return;
    }

    if (_profiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add someone first, then you can act on this.'),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Who is this about?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ..._profiles.map(
              (p) => ListTile(
                title: Text(p.name),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RelationshipDetailScreen(profile: p),
                    ),
                  ).then((_) => _load());
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('People & Clients'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: _addProfile,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      SoftLandingPanel(signal: _distressSignal),
                      const PromisesSummaryTile(),
                      const SizedBox(height: 8),
                      OneGoodMoveTile(
                        recentMoods: _recentMoods,
                        promisesOutstanding: _promisesOutstanding,
                        daysSinceLastContact: _daysSinceLastContact,
                        onAction: _handleOneGoodMoveAction,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _profiles.isEmpty
                      ? const Center(
                          child: Text(
                            'No profiles yet.\nAdd someone you want to care for better.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: _profiles.length,
                          itemBuilder: (context, index) {
                            final p = _profiles[index];
                            return ListTile(
                              title: Text(p.name),
                              subtitle: Text(
                                'Care: ${p.careScore.toStringAsFixed(0)} · Open promises: ${p.openPromiseCount}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        RelationshipDetailScreen(profile: p),
                                  ),
                                ).then((_) => _load());
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
