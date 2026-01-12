import 'package:flutter/material.dart';

import '../models/journal_entry.dart';
import '../services/conflict_resolution_service.dart';

class ConflictResolutionScreen extends StatefulWidget {
  final JournalEntry local;
  final JournalEntry remote;

  const ConflictResolutionScreen({
    Key? key,
    required this.local,
    required this.remote,
  }) : super(key: key);

  @override
  _ConflictResolutionScreenState createState() =>
      _ConflictResolutionScreenState();
}

class _ConflictResolutionScreenState extends State<ConflictResolutionScreen> {
  final _resolver = ConflictResolutionService();
  JournalEntry? _chosen;

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resolve Conflict')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Local Entry:\n${widget.local.content}'),
            const SizedBox(height: 16),
            Text('Remote Entry:\n${widget.remote.content}'),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                // Placeholder resolver; keep local.
                await _resolver.resolve(widget.local, widget.remote);
                if (!mounted) return;
                setState(() => _chosen = widget.local);
                Navigator.pop(ctx, widget.local);
              },
              child: const Text('Keep Local'),
            ),
            ElevatedButton(
              onPressed: () async {
                // Placeholder resolver; keep remote.
                await _resolver.resolve(widget.local, widget.remote);
                if (!mounted) return;
                setState(() => _chosen = widget.remote);
                Navigator.pop(ctx, widget.remote);
              },
              child: const Text('Keep Remote'),
            ),
            if (_chosen != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const Text('Chosen (preview):'),
              Text(_chosen!.content),
            ],
          ],
        ),
      ),
    );
  }
}
