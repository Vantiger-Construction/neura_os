import 'package:flutter/material.dart';

import '../services/trusted_contacts_service.dart';
import '../services/crisis_playbook_service.dart';
import '../models/crisis_playbook.dart';
import 'trusted_contacts_screen.dart';
import 'crisis_playbook_detail_screen.dart';

class CareModeHomeScreen extends StatefulWidget {
  const CareModeHomeScreen({super.key});

  @override
  State<CareModeHomeScreen> createState() => _CareModeHomeScreenState();
}

class _CareModeHomeScreenState extends State<CareModeHomeScreen> {
  final _contactsService = TrustedContactsService.instance;
  final _playbookService = CrisisPlaybookService.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _contactsService.load();
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  void _openPlaybook(CrisisPlaybook playbook) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CrisisPlaybookDetailScreen(playbook: playbook),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final emergencyContacts = _contactsService.emergencyContacts;
    final playbooks = _playbookService.playbooks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Care Mode'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.warning_amber, color: Colors.red),
                              SizedBox(width: 8),
                              Text(
                                'If this is an emergency:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Contact local emergency services or a crisis hotline '
                            'immediately. Neura can offer support, but cannot '
                            'respond in real time or replace professional help.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.contacts),
                    title: const Text('Trusted Contacts'),
                    subtitle: const Text(
                      'People you can reach out to when things feel heavy.',
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TrustedContactsScreen(),
                        ),
                      );
                    },
                  ),
                  if (emergencyContacts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0, right: 16.0),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: emergencyContacts
                            .map(
                              (c) => Chip(
                                avatar: const Icon(Icons.warning_amber, size: 16),
                                label: Text(c.name),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  const Divider(),
                  const ListTile(
                    leading: Icon(Icons.menu_book),
                    title: Text('Crisis Playbooks'),
                    subtitle: Text('Step-by-step plans for tough moments.'),
                  ),
                  ...playbooks.map((p) {
                    return Card(
                      child: ListTile(
                        title: Text(p.title),
                        subtitle: Text(
                          p.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _openPlaybook(p),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  const Text(
                    'Care Mode is here to help you feel less alone and to make it '
                    'easier to reach out for support. It does not replace mental '
                    'health professionals or emergency services.',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
    );
  }
}
