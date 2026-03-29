import 'package:flutter/material.dart';
import '../models/journal_entry.dart';
import '../services/conflict_resolution_service.dart';

class ConflictResolutionScreen extends StatefulWidget {
  final JournalEntry local;
  final JournalEntry remote;

  const ConflictResolutionScreen({
    super.key,
    required this.local,
    required this.remote,
  });

  @override
  _ConflictResolutionScreenState createState() =>
      _ConflictResolutionScreenState();
}

class _ConflictResolutionScreenState extends State<ConflictResolutionScreen> {
  final _resolver = ConflictResolutionService();

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: Text('Resolve Conflict')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Local Entry:\n${widget.local.content}'),
            SizedBox(height: 16),
            Text('Remote Entry:\n${widget.remote.content}'),
            SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                final choice =
                    await _resolver.resolve(widget.local, widget.remote);
                Navigator.pop(ctx, choice);
              },
              child: Text('Keep Local'),
            ),
            ElevatedButton(
              onPressed: () async {
                final choice =
                    await _resolver.resolve(widget.local, widget.remote);
                Navigator.pop(ctx, choice);
              },
              child: Text('Keep Remote'),
            ),
          ],
        ),
      ),
    );
  }
}
