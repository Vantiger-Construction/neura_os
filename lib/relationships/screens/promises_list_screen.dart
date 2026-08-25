import 'package:flutter/material.dart';
import '../services/promise_service.dart';
import '../models/neura_promise.dart';

class PromisesListScreen extends StatefulWidget {
  const PromisesListScreen({super.key});

  @override
  State<PromisesListScreen> createState() => _PromisesListScreenState();
}

class _PromisesListScreenState extends State<PromisesListScreen> {
  List<NeuraPromise> _promises = [];
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
      _promises = list;
      _loading = false;
    });
  }

  Future<void> _markDone(NeuraPromise p) async {
    await PromiseService.instance.updateStatus(p.id, PromiseStatus.completed);
    await _load();
  }

  Future<void> _markDropped(NeuraPromise p) async {
    await PromiseService.instance.updateStatus(p.id, PromiseStatus.dropped);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Promises')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _promises.isEmpty
              ? const Center(
                  child: Text(
                    'Nothing open.\nFuture You is proud of this.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: _promises.length,
                  itemBuilder: (context, index) {
                    final p = _promises[index];
                    return ListTile(
                      title: Text(p.description),
                      subtitle: p.dueAt != null
                          ? Text('Due ${p.dueAt}')
                          : const Text('No due date'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'done') _markDone(p);
                          if (value == 'drop') _markDropped(p);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'done',
                            child: Text('Mark as done'),
                          ),
                          PopupMenuItem(
                            value: 'drop',
                            child: Text('Drop (no longer relevant)'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
