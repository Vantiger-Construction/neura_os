import 'package:flutter/material.dart';

import '../../widgets/neura_explain.dart';
import 'memory_vault_models.dart';
import 'memory_vault_store.dart';
import 'vault_session.dart';

class MemoryVaultScreen extends StatefulWidget {
  const MemoryVaultScreen({super.key});

  @override
  State<MemoryVaultScreen> createState() => _MemoryVaultScreenState();
}

class _MemoryVaultScreenState extends State<MemoryVaultScreen> {
  bool _loading = true;
  List<VaultItem> _items = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ok = await VaultSession.ensureUnlocked(context);
    if (!mounted) return;
    if (!ok) {
      setState(() => _loading = false);
      return;
    }
    final pin = VaultSession.sessionPin!;
    final items = await MemoryVaultStore.instance.getItems(pin: pin);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _addItem() async {
    final pin = VaultSession.sessionPin;
    if (pin == null) {
      await _load();
      return;
    }

    final title = TextEditingController();
    final body = TextEditingController();
    final tags = TextEditingController();
    String titleValue = '';
    String bodyValue = '';
    String tagsValue = '';
    bool? ok;

    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('New Vault Entry'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Title')),
                  TextField(
                    controller: body,
                    decoration: const InputDecoration(labelText: 'Body'),
                    minLines: 3,
                    maxLines: 6,
                  ),
                  TextField(
                    controller: tags,
                    decoration: const InputDecoration(
                        labelText: 'Tags (comma separated)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Save')),
            ],
          );
        },
      );
      if (ok == true) {
        titleValue = title.text.trim();
        bodyValue = body.text.trim();
        tagsValue = tags.text;
      }
    } finally {
      title.dispose();
      body.dispose();
      tags.dispose();
    }

    if (ok != true) return;
    await MemoryVaultStore.instance.add(
      pin: pin,
      title: titleValue.isEmpty ? 'Untitled' : titleValue,
      body: bodyValue,
      tags: tagsValue
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(),
    );

    if (!mounted) return;
    await _load();
  }

  Future<void> _delete(String id) async {
    final pin = VaultSession.sessionPin;
    if (pin == null) {
      await _load();
      return;
    }
    await MemoryVaultStore.instance.delete(pin: pin, id: id);
    if (!mounted) return;
    await _load();
  }

  Future<void> _wipe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wipe Vault'),
        content: const Text(
            'This permanently removes all vault entries and the PIN verifier.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Wipe')),
        ],
      ),
    );
    if (ok != true) return;

    await MemoryVaultStore.instance.wipe();
    VaultSession.lock();
    if (!mounted) return;
    setState(() {
      _items = const [];
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory Vault'),
        actions: [
          IconButton(
            tooltip: 'Explain',
            onPressed: () => NeuraExplain.show(
              context,
              title: 'Memory Vault',
              body:
                  'Encrypted notes for the stuff that matters.\n\nSecurity: Your PIN is never stored. You enter it once per app session to unlock the vault.',
            ),
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: 'Lock',
            onPressed: () {
              VaultSession.lock();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Vault locked for this session.')),
              );
            },
            icon: const Icon(Icons.lock_outline),
          ),
          IconButton(
            tooltip: 'Wipe',
            onPressed: _wipe,
            icon: const Icon(Icons.delete_forever_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addItem,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No vault entries yet.'))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final it = _items[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: ListTile(
                        title: Text(it.title),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            Text(it.body),
                            if (it.tags.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: it.tags
                                    .map((t) => Chip(
                                        label: Text(t),
                                        visualDensity: VisualDensity.compact))
                                    .toList(),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              '${it.createdAt.toLocal()}'.split('.').first,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(it.id),
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
    );
  }
}
