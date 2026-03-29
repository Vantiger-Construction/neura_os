import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'legacy_trusted_contacts_service.dart';
import 'legacy_vault_service.dart';
import 'models/legacy_capsule.dart';
import 'models/trusted_contact.dart';

class LegacyEditorScreen extends StatefulWidget {
  final String? capsuleId;
  const LegacyEditorScreen({super.key, this.capsuleId});

  @override
  State<LegacyEditorScreen> createState() => _LegacyEditorScreenState();
}

class _LegacyEditorScreenState extends State<LegacyEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();

  late final String _draftId;
  bool _didPromptDecrypt = false;

  bool _encrypted = false;
  bool _sealed = false;
  DateTime? _unlockAt;

  // Delivery fields
  bool _deliveryEnabled = false;
  String _deliveryTrigger = 'manual';
  String _deliveryFormat = 'zip';
  List<String> _deliveryContactIds = [];

  List<String> _recipients = [];
  List<String> _tags = [];
  List<String> _attachmentsRel = [];

  bool _loading = false;
  LegacyCapsule? _existing;

  @override
  void initState() {
    super.initState();
    _draftId = widget.capsuleId ?? LegacyVaultService.instance.newId();
    if (widget.capsuleId != null) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final c = await LegacyVaultService.instance.loadCapsule(widget.capsuleId!);
    if (!mounted) return;

    if (c == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _existing = c;
      _title.text = c.title;
      _body.text = c.body;
      _encrypted = c.isEncrypted;
      _sealed = c.isSealed;
      _unlockAt = c.unlockAt;
      _recipients = [...c.recipients];
      _tags = [...c.tags];
      _attachmentsRel = [...c.attachments];
      _deliveryEnabled = c.deliveryEnabled;
      _deliveryTrigger = c.deliveryTrigger;
      _deliveryFormat = c.deliveryFormat;
      _deliveryContactIds = [...c.deliveryContactIds];
      _loading = false;
    });

    // If encrypted, offer a one-time decrypt prompt so the user can actually edit the body.
    if (!_didPromptDecrypt && c.isEncrypted) {
      _didPromptDecrypt = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final pass =
            await _promptPassphrase(title: 'Passphrase to edit this capsule');
        if (pass == null || pass.trim().isEmpty) return;
        try {
          final body = await LegacyVaultService.instance
              .decryptBody(capsule: c, passphrase: pass);
          if (!mounted) return;
          setState(() => _body.text = body);
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Passphrase incorrect (or capsule corrupted).')),
          );
        }
      });
    }
  }

  Future<void> _pickUnlockDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 20),
      initialDate: _unlockAt ?? now,
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_unlockAt ?? now),
    );
    if (time == null) return;

    setState(() {
      _unlockAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _addRecipient() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add recipient'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Name / email / handle',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add')),
        ],
      ),
    );

    if (ok != true) return;
    final v = controller.text.trim();
    if (v.isEmpty) return;
    setState(() {
      _recipients = [..._recipients, v];
    });
  }

  Future<void> _addRecipientFromTrusted() async {
    final contacts = await LegacyTrustedContactsService.instance.listContacts();
    if (!mounted) return;

    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No trusted contacts yet. Add some first.')),
      );
      return;
    }

    final picked = await showDialog<List<TrustedContact>>(
      context: context,
      builder: (_) => _TrustedContactPickerDialog(contacts: contacts),
    );

    if (picked == null || picked.isEmpty) return;

    setState(() {
      final asRecipients =
          picked.map((c) => '${c.displayName} <${c.address}>').toList();
      _recipients = {..._recipients, ...asRecipients}.toList();
      _deliveryContactIds =
          {..._deliveryContactIds, ...picked.map((c) => c.id)}.toList();
    });
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add tag'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Tag'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    final v = controller.text.trim();
    if (v.isEmpty) return;
    setState(() {
      _tags = [..._tags, v];
    });
  }

  Future<void> _importAttachment() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null || path.trim().isEmpty) return;

    final rel = await LegacyVaultService.instance.importAttachment(
      capsuleId: _draftId,
      sourcePath: path,
    );

    setState(() {
      _attachmentsRel = [..._attachmentsRel, rel];
    });
  }

  Future<void> _save() async {
    setState(() => _loading = true);

    final now = DateTime.now();

    // If encrypted, we store empty body and require the encryption flow handled by vault service.
    LegacyCapsule capsule = LegacyCapsule(
      id: _draftId,
      title: _title.text.trim(),
      body: _body.text,
      createdAt: _existing?.createdAt ?? now,
      updatedAt: now,
      recipients: _recipients,
      tags: _tags,
      unlockAt: _unlockAt,
      isSealed: _sealed,
      isEncrypted: _encrypted,
      attachments: _attachmentsRel,
      deliveryEnabled: _deliveryEnabled,
      deliveryTrigger: _deliveryTrigger,
      deliveryFormat: _deliveryFormat,
      deliveryContactIds: _deliveryContactIds,
    );

    try {
      if (_encrypted) {
        final pass = await _promptPassphrase();
        if (pass == null || pass.trim().isEmpty) {
          setState(() => _loading = false);
          return;
        }
        capsule = await LegacyVaultService.instance
            .saveCapsule(capsule, passphrase: pass);
      } else {
        capsule = await LegacyVaultService.instance.saveCapsule(capsule);
      }

      if (!mounted) return;
      Navigator.pop(context, capsule.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _promptPassphrase(
      {String title = 'Encryption passphrase'}) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Passphrase'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Encrypt')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.capsuleId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Capsule' : 'New Capsule'),
        actions: [
          IconButton(
            tooltip: 'Save',
            onPressed: _loading ? null : _save,
            icon: const Icon(Icons.save),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _body,
                  decoration: const InputDecoration(labelText: 'Message'),
                  maxLines: 8,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _encrypted,
                  onChanged: (v) => setState(() => _encrypted = v),
                  title: const Text('Encrypt this capsule'),
                  subtitle: const Text(
                      'Protects the message text. Attachments are stored locally; share packets carefully.'),
                ),
                SwitchListTile(
                  value: _sealed,
                  onChanged: (v) => setState(() => _sealed = v),
                  title: const Text('Seal (read‑only)'),
                  subtitle: const Text(
                      'Sealed capsules can’t be edited — duplicate to change.'),
                ),
                ListTile(
                  title: const Text('Time‑lock'),
                  subtitle: Text(_unlockAt == null
                      ? 'None'
                      : _unlockAt!.toLocal().toString()),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      if (_unlockAt != null)
                        IconButton(
                          tooltip: 'Clear',
                          onPressed: () => setState(() => _unlockAt = null),
                          icon: const Icon(Icons.clear),
                        ),
                      IconButton(
                        tooltip: 'Set',
                        onPressed: _pickUnlockDate,
                        icon: const Icon(Icons.schedule),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Recipients',
                                style: Theme.of(context).textTheme.titleMedium),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Add from trusted',
                              onPressed: _addRecipientFromTrusted,
                              icon: const Icon(Icons.verified_user_outlined),
                            ),
                            IconButton(
                              tooltip: 'Add',
                              onPressed: _addRecipient,
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                        if (_recipients.isEmpty)
                          const Text('None')
                        else
                          Wrap(
                            spacing: 8,
                            children: _recipients
                                .map(
                                  (r) => InputChip(
                                    label: Text(r),
                                    onDeleted: () => setState(() =>
                                        _recipients = _recipients
                                            .where((x) => x != r)
                                            .toList()),
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Tags',
                                style: Theme.of(context).textTheme.titleMedium),
                            const Spacer(),
                            IconButton(
                                tooltip: 'Add',
                                onPressed: _addTag,
                                icon: const Icon(Icons.add)),
                          ],
                        ),
                        if (_tags.isEmpty)
                          const Text('None')
                        else
                          Wrap(
                            spacing: 8,
                            children: _tags
                                .map(
                                  (t) => InputChip(
                                    label: Text(t),
                                    onDeleted: () => setState(() => _tags =
                                        _tags.where((x) => x != t).toList()),
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Attachments',
                                style: Theme.of(context).textTheme.titleMedium),
                            const Spacer(),
                            IconButton(
                                tooltip: 'Add file',
                                onPressed: _importAttachment,
                                icon: const Icon(Icons.attach_file)),
                          ],
                        ),
                        if (_attachmentsRel.isEmpty)
                          const Text('None')
                        else
                          ..._attachmentsRel.map(
                            (p) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading:
                                  const Icon(Icons.insert_drive_file_outlined),
                              title: Text(p.split('/').last),
                              subtitle: Text(p),
                              trailing: IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => setState(() =>
                                    _attachmentsRel = _attachmentsRel
                                        .where((x) => x != p)
                                        .toList()),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Delivery',
                                style: Theme.of(context).textTheme.titleMedium),
                            const Spacer(),
                            Switch(
                              value: _deliveryEnabled,
                              onChanged: (v) =>
                                  setState(() => _deliveryEnabled = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Mark this capsule as “deliverable” so it can be bundled into Legacy Packets (manual, time‑lock, or Legacy Guard).',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        if (_deliveryEnabled) ...[
                          DropdownButtonFormField<String>(
                            initialValue: _deliveryTrigger,
                            decoration:
                                const InputDecoration(labelText: 'Trigger'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'manual', child: Text('Manual')),
                              DropdownMenuItem(
                                  value: 'unlock',
                                  child: Text('After time‑lock')),
                              DropdownMenuItem(
                                  value: 'deadman',
                                  child: Text('Legacy Guard')),
                            ],
                            onChanged: (v) => setState(
                                () => _deliveryTrigger = v ?? 'manual'),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _deliveryFormat,
                            decoration: const InputDecoration(
                                labelText: 'Preferred format'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'zip', child: Text('ZIP packet')),
                              DropdownMenuItem(
                                  value: 'pdf', child: Text('PDF letter')),
                              DropdownMenuItem(
                                  value: 'json', child: Text('Raw JSON')),
                            ],
                            onChanged: (v) =>
                                setState(() => _deliveryFormat = v ?? 'zip'),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _deliveryContactIds.isEmpty
                                ? 'No trusted contacts linked (recipients list will be used).'
                                : 'Linked trusted contacts: ${_deliveryContactIds.length}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ],
            ),
    );
  }
}

class _TrustedContactPickerDialog extends StatefulWidget {
  final List<TrustedContact> contacts;
  const _TrustedContactPickerDialog({required this.contacts});

  @override
  State<_TrustedContactPickerDialog> createState() =>
      _TrustedContactPickerDialogState();
}

class _TrustedContactPickerDialogState
    extends State<_TrustedContactPickerDialog> {
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pick trusted contacts'),
      content: SizedBox(
        width: 420,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.contacts.length,
          itemBuilder: (context, i) {
            final c = widget.contacts[i];
            final selected = _selectedIds.contains(c.id);
            return CheckboxListTile(
              value: selected,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selectedIds.add(c.id);
                } else {
                  _selectedIds.remove(c.id);
                }
              }),
              title: Text(c.displayName),
              subtitle: Text(c.address),
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final picked = widget.contacts
                .where((c) => _selectedIds.contains(c.id))
                .toList();
            Navigator.pop(context, picked);
          },
          child: const Text('Use'),
        ),
      ],
    );
  }
}
