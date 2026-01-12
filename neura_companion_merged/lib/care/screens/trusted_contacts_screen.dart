import 'package:flutter/material.dart';

import '../models/trusted_contact.dart';
import '../services/trusted_contacts_service.dart';
import 'edit_trusted_contact_screen.dart';

class TrustedContactsScreen extends StatefulWidget {
  const TrustedContactsScreen({super.key});

  @override
  State<TrustedContactsScreen> createState() => _TrustedContactsScreenState();
}

class _TrustedContactsScreenState extends State<TrustedContactsScreen> {
  final _service = TrustedContactsService.instance;
  bool _loading = true;
  List<TrustedContact> _contacts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _service.load();
    if (!mounted) return;
    setState(() {
      _contacts = _service.contacts;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const EditTrustedContactScreen(),
      ),
    );
    if (result == true) {
      await _load();
    }
  }

  Future<void> _edit(TrustedContact contact) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditTrustedContactScreen(existing: contact),
      ),
    );
    if (result == true) {
      await _load();
    }
  }

  Future<void> _delete(TrustedContact contact) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove contact'),
        content: Text('Remove ${contact.name} from your trusted contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _service.delete(contact.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trusted Contacts'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'Add a few people you trust so Neura can remind you who to reach out to '
                      'when things feel heavy.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _contacts.length,
                  itemBuilder: (ctx, i) {
                    final c = _contacts[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          c.isEmergency
                              ? Icons.warning_amber
                              : (c.isProfessional
                                  ? Icons.medical_information
                                  : Icons.person),
                        ),
                        title: Text(c.name),
                        subtitle: Text(
                          [
                            if (c.relationship.isNotEmpty) c.relationship,
                            if (c.phoneNumber.isNotEmpty) c.phoneNumber,
                          ].join(' · '),
                        ),
                        onTap: () => _edit(c),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _delete(c),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
