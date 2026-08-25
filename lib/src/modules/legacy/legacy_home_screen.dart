import 'package:flutter/material.dart';

import 'legacy_detail_screen.dart';
import 'legacy_editor_screen.dart';
import 'legacy_guard_screen.dart';
import 'legacy_templates_screen.dart';
import 'legacy_trusted_contacts_screen.dart';
import 'legacy_vault_tools_screen.dart';
import 'legacy_vault_service.dart';
import 'models/legacy_capsule.dart';

class LegacyHomeScreen extends StatefulWidget {
  const LegacyHomeScreen({super.key});

  @override
  State<LegacyHomeScreen> createState() => _LegacyHomeScreenState();
}

class _LegacyHomeScreenState extends State<LegacyHomeScreen> {
  late Future<List<LegacyCapsule>> _future;

  @override
  void initState() {
    super.initState();
    _future = LegacyVaultService.instance.listCapsules();
  }

  Future<void> _reload() async {
    setState(() {
      _future = LegacyVaultService.instance.listCapsules();
    });
  }

  Future<void> _openNew() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LegacyEditorScreen()),
    );
    await _reload();
  }

  Future<void> _openCapsule(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LegacyDetailScreen(capsuleId: id)),
    );
    await _reload();
  }

  Future<void> _openTrustedContacts() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LegacyTrustedContactsScreen()),
    );
  }

  Future<void> _openTemplates() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LegacyTemplatesScreen()),
    );
  }

  Future<void> _openVaultTools() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LegacyVaultToolsScreen()),
    );
  }

  Future<void> _openGuard() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LegacyGuardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Legacy Vault'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _openNew, icon: const Icon(Icons.add)),
        ],
      ),
      body: FutureBuilder<List<LegacyCapsule>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text('Trusted Contacts'),
                      subtitle: const Text(
                          'Keep a clean list of people (or destinations) for delivery.'),
                      onTap: _openTrustedContacts,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.message_outlined),
                      title: const Text('Message Templates'),
                      subtitle: const Text(
                          'Quick "send to grandma" style messages for sharing packets.'),
                      onTap: _openTemplates,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: const Text('Vault Backup & Restore'),
                      subtitle: const Text(
                          'Export a local ZIP backup or import one.'),
                      onTap: _openVaultTools,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.shield_outlined),
                      title: const Text('Legacy Guard'),
                      subtitle: const Text(
                          'Dead‑man switch style check‑ins & release packets.'),
                      onTap: _openGuard,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Capsules',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  Text('${items.length}',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No capsules yet.')))
              else
                ...items.map(
                  (c) => Card(
                    child: ListTile(
                      title: Text(c.title.isEmpty ? '(Untitled)' : c.title),
                      subtitle: Text(
                        '${c.createdAt.toLocal().toString().substring(0, 16)}'
                        '${c.unlockAt == null ? '' : ' • Unlock: ${c.unlockAt!.toLocal().toString().substring(0, 16)}'}'
                        '${c.isEncrypted ? ' • Encrypted' : ''}'
                        '${c.isSealed ? ' • Sealed' : ''}'
                        '${c.deliveryEnabled ? ' • Delivery: ${c.deliveryTrigger}' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openCapsule(c.id),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
