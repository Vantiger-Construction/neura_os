import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'legacy_delivery_service.dart';
import 'legacy_editor_screen.dart';
import 'legacy_send_screen.dart';
import 'legacy_trusted_contacts_screen.dart';
import 'legacy_trusted_contacts_service.dart';
import 'legacy_vault_service.dart';
import 'models/legacy_capsule.dart';

class LegacyDetailScreen extends StatefulWidget {
  final String capsuleId;
  const LegacyDetailScreen({super.key, required this.capsuleId});

  @override
  State<LegacyDetailScreen> createState() => _LegacyDetailScreenState();
}

class _LegacyDetailScreenState extends State<LegacyDetailScreen> {
  late Future<LegacyCapsule?> _future;

  @override
  void initState() {
    super.initState();
    _future = LegacyVaultService.instance.loadCapsule(widget.capsuleId);
  }

  Future<void> _reload() async {
    setState(() {
      _future = LegacyVaultService.instance.loadCapsule(widget.capsuleId);
    });
  }

  Future<String?> _promptPassphrase({required String title}) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Passphrase',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Continue')),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openEditor(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LegacyEditorScreen(capsuleId: id)),
    );
    await _reload();
  }

  Future<void> _duplicate(String id) async {
    try {
      final dup = await LegacyVaultService.instance.duplicateCapsule(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Duplicated. Editing the copy.')),
      );
      await _openEditor(dup.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Duplicate failed: $e')),
      );
    }
  }

  
  bool _looksLikeGrandma(String s) {
    final v = s.toLowerCase();
    return v.contains('grandma') || v.contains('gramma') || v.contains('granny') || v.contains('nana') || v.contains('nan');
  }

  Future<void> _oneTapGrandma(LegacyCapsule c) async {
    try {
      final contacts = await LegacyTrustedContactsService.instance.listContacts();
      final grandma = contacts.where((x) => _looksLikeGrandma(x.displayName) || _looksLikeGrandma(x.note)).toList();
      if (grandma.isEmpty) {
        if (!mounted) return;
        final add = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('No "Grandma" contact yet'),
            content: const Text('Add a trusted contact named "Grandma" (or Nana/Granny) to enable one‑tap sending.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add contact')),
            ],
          ),
        );
        if (add == true) {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LegacyTrustedContactsScreen()));
        }
        return;
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LegacySendScreen(
            capsule: c,
            initialContactId: grandma.first.id,
            initialTemplateId: 'tpl_grandma',
            initialFormat: 'zip',
            autoOpenShareSheet: true,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Grandma send failed: $e')));
    }
  }

  Future<void> _exportPdfLetter(LegacyCapsule c) async {
    try {
      final xfile = await LegacyDeliveryService.instance.createDeliveryPacket(
        capsule: c,
        preferFormat: 'pdf',
        decryptIfPossible: true,
        context: context,
      );
      await Share.shareXFiles(
        [xfile],
        text: 'Neura Legacy Letter — ${c.title.isEmpty ? 'capsule' : c.title}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
    }
  }

Future<void> _shareDeliveryPacket(LegacyCapsule c) async {
    try {
      final xfile = await LegacyDeliveryService.instance.createDeliveryPacket(
        capsule: c,
        preferFormat: c.deliveryFormat,
        decryptIfPossible: true,
        context: context,
      );
      await Share.shareXFiles(
        [xfile],
        text: 'Neura Legacy Packet — ${c.title.isEmpty ? 'capsule' : c.title}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Packet export failed: $e')),
      );
    }
  }

  Future<void> _shareJson(LegacyCapsule c) async {
    try {
      String? pass;
      bool decrypted = false;
      if (c.isEncrypted) {
        final action = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Export JSON'),
            content: const Text('Export encrypted as-is, or decrypt first (requires passphrase)?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, 'raw'), child: const Text('Raw')),
              ElevatedButton(onPressed: () => Navigator.pop(context, 'decrypt'), child: const Text('Decrypt')),
            ],
          ),
        );
        if (action == null) return;
        if (action == 'decrypt') {
          pass = await _promptPassphrase(title: 'Passphrase');
          if (pass == null || pass.trim().isEmpty) return;
          decrypted = true;
        }
      }

      final file = await LegacyVaultService.instance.exportCapsule(
        c.id,
        passphrase: pass,
        decrypted: decrypted,
      );
      await Share.shareXFiles([XFile(file.path)], text: 'Legacy Capsule export (.json)');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete capsule?'),
        content: const Text('This deletes the capsule and attachments from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;
    await LegacyVaultService.instance.deleteCapsule(id);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Legacy Capsule'),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<LegacyCapsule?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final c = snap.data;
          if (c == null) {
            return const Center(child: Text('Not found.'));
          }

          final locked = c.isLocked;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                c.title.isEmpty ? '(Untitled)' : c.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(locked ? 'Locked until ${c.unlockAt!.toLocal().toString().substring(0, 16)}' : 'Unlocked')),
                  if (c.isSealed) const Chip(label: Text('Sealed')),
                  if (c.isEncrypted) const Chip(label: Text('Encrypted')),
                  if (c.deliveryEnabled) Chip(label: Text('Delivery: ${c.deliveryTrigger} • ${c.deliveryFormat}')),
                ],
              ),
              const SizedBox(height: 16),

              if (locked)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      "This capsule is time‑locked. You can still edit metadata unless it's sealed.",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Message', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        c.isEncrypted
                            ? '(Encrypted — use Packet or JSON export to decrypt.)'
                            : (c.body.isEmpty ? '(Empty)' : c.body),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (c.attachments.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Attachments', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        ...c.attachments.map(
                          (p) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.attach_file),
                            title: Text(p.split('/').last),
                            subtitle: Text(p),
                            onTap: () async {
                              final f = await LegacyVaultService.instance.resolveAttachmentFile(p);
                              await Share.shareXFiles([XFile(f.path)], text: 'Attachment from Legacy Capsule');
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: c.isSealed ? () => _duplicate(c.id) : () => _openEditor(c.id),
                    icon: Icon(c.isSealed ? Icons.copy : Icons.edit),
                    label: Text(c.isSealed ? 'Duplicate to Edit' : 'Edit'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => LegacySendScreen(capsule: c)),
                      );
                    },
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Send'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _oneTapGrandma(c),
                    icon: const Icon(Icons.favorite_border),
                    label: const Text('Grandma'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _exportPdfLetter(c),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _shareDeliveryPacket(c),
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text('Export Packet'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _shareJson(c),
                    icon: const Icon(Icons.code),
                    label: const Text('JSON'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _delete(c.id),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
