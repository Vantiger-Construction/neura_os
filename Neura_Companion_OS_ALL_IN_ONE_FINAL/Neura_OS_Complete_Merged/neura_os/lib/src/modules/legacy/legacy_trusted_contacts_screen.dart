import 'package:flutter/material.dart';

import 'legacy_trusted_contacts_service.dart';
import 'legacy_vault_service.dart';
import 'models/trusted_contact.dart';

class LegacyTrustedContactsScreen extends StatefulWidget {
  const LegacyTrustedContactsScreen({super.key});

  @override
  State<LegacyTrustedContactsScreen> createState() => _LegacyTrustedContactsScreenState();
}

class _LegacyTrustedContactsScreenState extends State<LegacyTrustedContactsScreen> {
  late Future<List<TrustedContact>> _future;

  @override
  void initState() {
    super.initState();
    _future = LegacyTrustedContactsService.instance.listContacts();
  }

  Future<void> _reload() async {
    setState(() {
      _future = LegacyTrustedContactsService.instance.listContacts();
    });
  }

  Future<void> _edit({TrustedContact? existing}) async {
    final name = TextEditingController(text: existing?.displayName ?? '');
    final addr = TextEditingController(text: existing?.address ?? '');
    final note = TextEditingController(text: existing?.note ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'New Trusted Contact' : 'Edit Trusted Contact'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g., “Aunt Sarah”',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: addr,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  hintText: 'email, phone label, handle, etc.',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'How to reach them, context, etc.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;

    final displayName = name.text.trim();
    final address = addr.text.trim();
    final memo = note.text.trim();

    if (displayName.isEmpty || address.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and address are required.')),
      );
      return;
    }

    final now = DateTime.now();
    final contact = TrustedContact(
      id: existing?.id ?? LegacyVaultService.instance.newId(),
      displayName: displayName,
      address: address,
      note: memo,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    await LegacyTrustedContactsService.instance.upsert(contact);
    await _reload();
  }

  Future<void> _delete(TrustedContact c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove trusted contact?'),
        content: Text('Remove “${c.displayName}” from your trusted list?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );

    if (ok != true) return;
    await LegacyTrustedContactsService.instance.deleteById(c.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trusted Contacts'),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add'),
      ),
      body: FutureBuilder<List<TrustedContact>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No trusted contacts yet.\n\nAdd people you’d want to receive a Legacy Packet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            );
          }

          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = items[i];
              return ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(c.displayName),
                subtitle: Text(c.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _edit(existing: c),
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(c),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
