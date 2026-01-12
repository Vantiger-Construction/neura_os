import 'package:flutter/material.dart';
import '../services/sync_service.dart';

class SyncStatusScreen extends StatefulWidget {
  @override
  _SyncStatusScreenState createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  final _sync = SyncService();
  bool _syncing = false;

  Future<void> _startSync() async {
    setState(() => _syncing = true);
    await _sync.syncAll();
    setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: Text('Sync Status')),
      body: Center(
        child: _syncing
            ? CircularProgressIndicator()
            : ElevatedButton(
                onPressed: _startSync,
                child: Text('Sync Now'),
              ),
      ),
    );
  }
}
