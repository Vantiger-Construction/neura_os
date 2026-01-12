import 'package:flutter/material.dart';

import 'mood_store.dart';

class MoodHistoryScreen extends StatefulWidget {
  const MoodHistoryScreen({super.key});

  @override
  State<MoodHistoryScreen> createState() => _MoodHistoryScreenState();
}

class _MoodHistoryScreenState extends State<MoodHistoryScreen> {
  bool _loading = true;
  List<_Row> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await MoodStore.instance.getAll();
    final rows = items.reversed.take(120).map((e) {
      final ts = e.timestamp;
      final when = '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} '
          '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
      return _Row(when, e.mood0to10, e.note);
    }).toList();
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mood History'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No check-ins yet.')),
                  )
                else
                  ..._rows.map(
                    (r) => Card(
                      child: ListTile(
                        title: Text('${r.when} • Mood ${r.mood}/10'),
                        subtitle: r.note.isEmpty ? null : Text(r.note),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Row {
  final String when;
  final int mood;
  final String note;
  const _Row(this.when, this.mood, this.note);
}
