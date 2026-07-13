
import 'package:flutter/material.dart';
import '../services/promise_service.dart';
import '../screens/promises_list_screen.dart';

class PromisesSummaryTile extends StatefulWidget {
  const PromisesSummaryTile({super.key});

  @override
  State<PromisesSummaryTile> createState() => _PromisesSummaryTileState();
}

class _PromisesSummaryTileState extends State<PromisesSummaryTile> {
  int _openCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await PromiseService.instance.openPromises();
    if (!mounted) return;
    setState(() {
      _openCount = list.length;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Checking your promises...'),
        ),
      );
    }

    return Card(
      child: ListTile(
        title: const Text('Promises'),
        subtitle: Text(
          _openCount == 0
              ? 'No open promises. Clean slate 🎯'
              : 'You have $_openCount open thing(s) you said you’d do.',
        ),
        trailing: const Icon(Icons.checklist_rounded),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PromisesListScreen()),
          ).then((_) => _load());
        },
      ),
    );
  }
}
