import 'package:flutter/material.dart';

import 'legacy_templates_service.dart';
import 'models/legacy_message_template.dart';

class LegacyTemplatesScreen extends StatefulWidget {
  const LegacyTemplatesScreen({super.key});

  @override
  State<LegacyTemplatesScreen> createState() => _LegacyTemplatesScreenState();
}

class _LegacyTemplatesScreenState extends State<LegacyTemplatesScreen> {
  late Future<List<LegacyMessageTemplate>> _future;

  @override
  void initState() {
    super.initState();
    _future = LegacyTemplatesService.instance.listTemplates();
  }

  Future<void> _reload() async {
    setState(() {
      _future = LegacyTemplatesService.instance.listTemplates();
    });
  }

  Future<void> _addOrEdit({LegacyMessageTemplate? existing}) async {
    final isEditing = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final bodyCtrl = TextEditingController(text: existing?.bodyTemplate ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEditing ? 'Edit template' : 'New template'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyCtrl,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Template body',
                  helperText: 'Placeholders: {contactName}, {capsuleTitle}, {date}, {appName}',
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

    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    if (name.isEmpty || body.isEmpty) return;

    final now = DateTime.now();
    final template = (existing ?? LegacyMessageTemplate(
          id: 'tpl_user_${now.millisecondsSinceEpoch}',
          name: name,
          bodyTemplate: body,
          createdAt: now,
          updatedAt: now,
          isBuiltIn: false,
        ))
        .copyWith(name: name, bodyTemplate: body, updatedAt: now);

    await LegacyTemplatesService.instance.upsertTemplate(template);
    await _reload();
  }

  Future<void> _delete(LegacyMessageTemplate t) async {
    if (t.isBuiltIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Built‑in templates can’t be deleted.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text('“${t.name}”'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await LegacyTemplatesService.instance.deleteTemplate(t.id);
    await _reload();
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset templates?'),
        content: const Text('This will restore Neura’s default templates. Your custom templates will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    await LegacyTemplatesService.instance.resetToDefaults();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Templates'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _reset, icon: const Icon(Icons.restart_alt)),
          IconButton(onPressed: () => _addOrEdit(), icon: const Icon(Icons.add)),
        ],
      ),
      body: FutureBuilder<List<LegacyMessageTemplate>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No templates.')));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final t = items[i];
              return Card(
                child: ListTile(
                  leading: Icon(t.isBuiltIn ? Icons.auto_fix_high : Icons.edit_note),
                  title: Text(t.name),
                  subtitle: Text(
                    t.bodyTemplate.replaceAll('\n', '  ').trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit),
                        onPressed: () => _addOrEdit(existing: t),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(t),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
