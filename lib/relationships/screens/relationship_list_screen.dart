
import 'package:flutter/material.dart';
import '../services/relationship_profile_service.dart';
import '../models/relationship_profile.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await RelationshipProfileService.instance.refreshOpenPromiseCounts();
    final list = await RelationshipProfileService.instance.all();
    if (!mounted) return;
    setState(() {
      _profiles = list;
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
    _load();
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
          : _profiles.isEmpty
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
    );
  }
}
