import 'package:flutter/material.dart';

import '../models/neura_promise.dart';
import '../services/promise_service.dart';

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

  Future<void> _showEditor([NeuraPromise? promise]) async {
    final draft = await showDialog<_PromiseDraft>(
      context: context,
      builder: (_) => _PromiseEditorDialog(promise: promise),
    );
    if (draft == null) return;

    try {
      if (promise == null) {
        await PromiseService.instance.create(
          description: draft.description,
          dueAt: draft.dueAt,
        );
      } else {
        await PromiseService.instance.update(
          promise.id,
          description: draft.description,
          dueAt: draft.dueAt,
          clearDueAt: promise.dueAt != null && draft.dueAt == null,
        );
      }
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The promise could not be saved locally.'),
        ),
      );
    }
  }

  Future<void> _markDone(NeuraPromise promise) async {
    await PromiseService.instance.updateStatus(
      promise.id,
      PromiseStatus.completed,
    );
    await _load();
  }

  Future<void> _markDropped(NeuraPromise promise) async {
    await PromiseService.instance.updateStatus(
      promise.id,
      PromiseStatus.dropped,
    );
    await _load();
  }

  String _dueLabel(NeuraPromise promise) {
    final dueAt = promise.dueAt;
    if (dueAt == null) return 'No due date';
    final local = dueAt.toLocal();
    final material = MaterialLocalizations.of(context);
    final date = material.formatMediumDate(local);
    final time = material.formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return 'Due $date at $time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Promises')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add promise'),
      ),
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
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: _promises.length,
                  itemBuilder: (context, index) {
                    final promise = _promises[index];
                    return ListTile(
                      title: Text(promise.description),
                      subtitle: Text(_dueLabel(promise)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'edit') await _showEditor(promise);
                          if (value == 'done') await _markDone(promise);
                          if (value == 'drop') await _markDropped(promise);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
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

class _PromiseDraft {
  const _PromiseDraft({
    required this.description,
    required this.dueAt,
  });

  final String description;
  final DateTime? dueAt;
}

class _PromiseEditorDialog extends StatefulWidget {
  const _PromiseEditorDialog({this.promise});

  final NeuraPromise? promise;

  @override
  State<_PromiseEditorDialog> createState() => _PromiseEditorDialogState();
}

class _PromiseEditorDialogState extends State<_PromiseEditorDialog> {
  late final TextEditingController _descriptionController;
  DateTime? _dueAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(
      text: widget.promise?.description ?? '',
    );
    _dueAt = widget.promise?.dueAt?.toLocal();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDueAt() async {
    final now = DateTime.now();
    final initial = _dueAt != null && _dueAt!.isAfter(now)
        ? _dueAt!
        : now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    setState(() {
      _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _error = null;
    });
  }

  String _dueLabel() {
    final dueAt = _dueAt;
    if (dueAt == null) return 'No reminder date';
    final material = MaterialLocalizations.of(context);
    final date = material.formatMediumDate(dueAt);
    final time = material.formatTimeOfDay(TimeOfDay.fromDateTime(dueAt));
    return '$date at $time';
  }

  void _submit() {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      setState(() => _error = 'Describe the promise first.');
      return;
    }
    if (_dueAt != null && !_dueAt!.isAfter(DateTime.now())) {
      setState(() => _error = 'Choose a future reminder time.');
      return;
    }
    Navigator.of(context).pop(
      _PromiseDraft(description: description, dueAt: _dueAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.promise != null;
    return AlertDialog(
      title: Text(editing ? 'Edit promise' : 'Add promise'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _descriptionController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What did you promise?',
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(_dueLabel()),
              subtitle: const Text(
                'Reminders follow your off-by-default notification setting.',
              ),
              onTap: _pickDueAt,
            ),
            if (_dueAt != null)
              TextButton.icon(
                onPressed: () => setState(() {
                  _dueAt = null;
                  _error = null;
                }),
                icon: const Icon(Icons.event_busy_outlined),
                label: const Text('Remove due date'),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Promises stay in Neura\'s local relationship store. Nothing is '
              'uploaded.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
