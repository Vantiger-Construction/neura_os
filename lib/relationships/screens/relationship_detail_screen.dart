
import 'package:flutter/material.dart';

import '../models/relationship_profile.dart';
import '../models/interaction_record.dart';
import '../models/neura_promise.dart';
import '../services/interaction_service.dart';
import '../services/promise_service.dart';
import '../widgets/relationship_quick_note_button.dart';

class RelationshipDetailScreen extends StatefulWidget {
  final RelationshipProfile profile;

  const RelationshipDetailScreen({super.key, required this.profile});

  @override
  State<RelationshipDetailScreen> createState() =>
      _RelationshipDetailScreenState();
}

class _RelationshipDetailScreenState extends State<RelationshipDetailScreen> {
  InteractionRecord? _lastInteraction;
  List<NeuraPromise> _promises = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final last = await InteractionService.instance
        .lastForProfile(widget.profile.id);
    final allPromises =
        await PromiseService.instance.forProfile(widget.profile.id);
    if (!mounted) return;
    setState(() {
      _lastInteraction = last;
      _promises = allPromises
          .where((p) => p.status == PromiseStatus.pending)
          .toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    return Scaffold(
      appBar: AppBar(
        title: Text(profile.name),
      ),
      floatingActionButton:
          RelationshipQuickNoteButton(profileId: profile.id),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(profile),
                  const SizedBox(height: 16),
                  _buildLastInteraction(),
                  const SizedBox(height: 16),
                  _buildPromises(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(RelationshipProfile profile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profile.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (profile.tags.isNotEmpty)
              Wrap(
                spacing: 8,
                children: profile.tags
                    .map((t) => Chip(label: Text(t)))
                    .toList(),
              ),
            const SizedBox(height: 8),
            Text(
              'Care score: ${profile.careScore.toStringAsFixed(0)} / 100',
              style: const TextStyle(fontSize: 13),
            ),
            if (profile.lastContact != null)
              Text(
                'Last contact: ${profile.lastContact}',
                style: const TextStyle(fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastInteraction() {
    if (_lastInteraction == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No interaction history yet.\nFirst step could be a short check-in.',
          ),
        ),
      );
    }

    final last = _lastInteraction!;

    String channelLabel;
    switch (last.channel) {
      case InteractionChannel.chat:
        channelLabel = 'Chat';
        break;
      case InteractionChannel.call:
        channelLabel = 'Call';
        break;
      case InteractionChannel.meeting:
        channelLabel = 'Meeting';
        break;
      case InteractionChannel.note:
        channelLabel = 'Note';
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Last interaction',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '$channelLabel · ${last.timestamp}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            if (last.contextSnippet.isNotEmpty)
              Text(
                last.contextSnippet,
                style: const TextStyle(fontSize: 14),
              ),
            if (last.summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                last.summary,
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if (last.nextStep.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Next step: ${last.nextStep}',
                style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPromises() {
    if (_promises.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No open promises just for this person.',
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Open promises to this person',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._promises.map(
              (p) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.description),
                subtitle: p.dueAt != null
                    ? Text('Due ${p.dueAt}')
                    : const Text('No due date'),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'done') {
                      await PromiseService.instance
                          .updateStatus(p.id, PromiseStatus.completed);
                    } else if (value == 'drop') {
                      await PromiseService.instance
                          .updateStatus(p.id, PromiseStatus.dropped);
                    }
                    await _load();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'done',
                      child: Text('Mark as done'),
                    ),
                    PopupMenuItem(
                      value: 'drop',
                      child: Text('Drop'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
