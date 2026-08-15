import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'legacy_delivery_service.dart';
import 'legacy_templates_service.dart';
import 'legacy_trusted_contacts_service.dart';
import 'models/legacy_capsule.dart';
import 'models/legacy_message_template.dart';
import 'models/trusted_contact.dart';

class LegacySendScreen extends StatefulWidget {
  final LegacyCapsule capsule;

  /// Optional preselects (used by "one‑tap Grandma" shortcuts).
  final String? initialContactId;
  final String? initialTemplateId;
  final String? initialFormat;

  /// If true, the screen will open and immediately trigger the share flow once
  /// it's fully loaded.
  final bool autoOpenShareSheet;

  const LegacySendScreen({
    super.key,
    required this.capsule,
    this.initialContactId,
    this.initialTemplateId,
    this.initialFormat,
    this.autoOpenShareSheet = false,
  });

  @override
  State<LegacySendScreen> createState() => _LegacySendScreenState();
}

class _LegacySendScreenState extends State<LegacySendScreen> {
  bool _loading = true;
  bool _autoTriggered = false;

  List<TrustedContact> _contacts = const [];
  List<LegacyMessageTemplate> _templates = const [];

  String? _selectedContactId;
  String? _selectedTemplateId;
  String _format = 'zip';
  bool _decryptIfPossible = false;

  final TextEditingController _messageCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _format = (widget.initialFormat ?? widget.capsule.deliveryFormat)
        .toLowerCase()
        .trim();
    if (_format != 'zip' && _format != 'pdf' && _format != 'json') {
      _format = 'zip';
    }

    _decryptIfPossible = widget.capsule.isEncrypted; // sensible default
    _boot();
  }

  bool _looksLikeGrandma(String s) {
    final v = s.toLowerCase();
    return v.contains('grandma') ||
        v.contains('gramma') ||
        v.contains('granny') ||
        v.contains('nana') ||
        v.contains('nan');
  }

  Future<void> _boot() async {
    final contacts = await LegacyTrustedContactsService.instance.listContacts();
    final templates = await LegacyTemplatesService.instance.listTemplates();

    // Pick template.
    String? pickTemplate = widget.initialTemplateId;
    if (pickTemplate != null && !templates.any((t) => t.id == pickTemplate)) {
      pickTemplate = null;
    }
    if (pickTemplate == null) {
      if (templates.any((t) => t.id == 'tpl_grandma')) {
        pickTemplate = 'tpl_grandma';
      } else if (templates.isNotEmpty) {
        pickTemplate = templates.first.id;
      }
    }

    // Pick contact.
    String? pickContact = widget.initialContactId;
    if (pickContact != null && !contacts.any((c) => c.id == pickContact)) {
      pickContact = null;
    }
    if (pickContact == null) {
      final grandma = contacts
          .where((c) =>
              _looksLikeGrandma(c.displayName) || _looksLikeGrandma(c.note))
          .toList();
      if (grandma.isNotEmpty) pickContact = grandma.first.id;
    }
    pickContact ??= contacts.isEmpty ? null : contacts.first.id;

    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _templates = templates;
      _selectedTemplateId = pickTemplate;
      _selectedContactId = pickContact;
      _loading = false;
    });

    _regenerateMessage();
    _maybeAutoSend();
  }

  void _maybeAutoSend() {
    if (!widget.autoOpenShareSheet) return;
    if (_autoTriggered) return;
    if (_loading) return;
    _autoTriggered = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _share();
    });
  }

  TrustedContact? get _selectedContact {
    if (_selectedContactId == null) return null;
    for (final c in _contacts) {
      if (c.id == _selectedContactId) return c;
    }
    return null;
  }

  LegacyMessageTemplate? get _selectedTemplate {
    if (_selectedTemplateId == null) return null;
    for (final t in _templates) {
      if (t.id == _selectedTemplateId) return t;
    }
    return null;
  }

  String _applyPlaceholders(String template, {TrustedContact? contact}) {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final cName = (contact?.displayName ?? 'there').trim().isEmpty
        ? 'there'
        : (contact?.displayName ?? 'there');
    final title =
        widget.capsule.title.isEmpty ? 'Legacy Capsule' : widget.capsule.title;
    return template
        .replaceAll('{contactName}', cName)
        .replaceAll('{capsuleTitle}', title)
        .replaceAll('{date}', date)
        .replaceAll('{appName}', 'Neura Companion');
  }

  void _regenerateMessage() {
    final t = _selectedTemplate;
    if (t == null) return;
    final text = _applyPlaceholders(t.bodyTemplate, contact: _selectedContact);
    setState(() => _messageCtrl.text = text);
  }

  Future<String?> _promptPassphrase() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Passphrase'),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration:
                const InputDecoration(labelText: 'Enter the passphrase'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Continue')),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _share() async {
    setState(() => _loading = true);
    try {
      String? pass;
      if (_decryptIfPossible && widget.capsule.isEncrypted) {
        pass = await _promptPassphrase();
        if (pass == null || pass.trim().isEmpty) {
          setState(() => _loading = false);
          return;
        }
      }

      final contact = _selectedContact;
      final deliveryNote =
          _messageCtrl.text.trim().isEmpty ? null : _messageCtrl.text.trim();

      final file = await LegacyDeliveryService.instance.createDeliveryPacket(
        capsule: widget.capsule,
        preferFormat: _format,
        decryptIfPossible: _decryptIfPossible,
        passphraseOverride: pass,
        recipientName: contact?.displayName,
        deliveryNote: deliveryNote,
        context: context,
      );

      final contactLine = contact == null
          ? ''
          : '\n\nRecipient: ${contact.displayName} <${contact.address}>';

      await LegacyDeliveryService.instance.shareFiles(
        filePaths: [file.path],
        text: '${_messageCtrl.text.trim()}$contactLine',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Share sheet opened.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Send failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capsule = widget.capsule;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Legacy Packet'),
        actions: [
          IconButton(
            tooltip: 'Regenerate message from template',
            onPressed: _loading ? null : _regenerateMessage,
            icon: const Icon(Icons.auto_fix_high),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          capsule.title.isEmpty
                              ? '(Untitled Capsule)'
                              : capsule.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${capsule.isEncrypted ? 'Encrypted' : 'Not encrypted'}'
                          '${capsule.unlockAt == null ? '' : ' • Time‑lock: ${capsule.unlockAt!.toLocal().toString().substring(0, 16)}'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _selectedContactId,
                  decoration: const InputDecoration(
                      labelText: 'Trusted contact (optional)'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None (choose recipient in share sheet)')),
                    ..._contacts.map((c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text('${c.displayName} (${c.address})'))),
                  ],
                  onChanged: (v) {
                    setState(() => _selectedContactId = v);
                    _regenerateMessage();
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _selectedTemplateId,
                  decoration:
                      const InputDecoration(labelText: 'Message template'),
                  items: _templates
                      .map((t) => DropdownMenuItem<String?>(
                          value: t.id, child: Text(t.name)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedTemplateId = v);
                    _regenerateMessage();
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _messageCtrl,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _format,
                  decoration: const InputDecoration(labelText: 'Packet format'),
                  items: const [
                    DropdownMenuItem(
                        value: 'zip', child: Text('ZIP packet (best)')),
                    DropdownMenuItem(value: 'pdf', child: Text('PDF letter')),
                    DropdownMenuItem(value: 'json', child: Text('JSON (raw)')),
                  ],
                  onChanged: (v) => setState(() => _format = v ?? _format),
                ),
                const SizedBox(height: 12),
                if (capsule.isEncrypted)
                  SwitchListTile(
                    value: _decryptIfPossible,
                    onChanged: (v) => setState(() => _decryptIfPossible = v),
                    title: const Text('Decrypt before sending'),
                    subtitle: const Text(
                        'Recipients can read without passphrase, but you must enter it now.'),
                  )
                else
                  const ListTile(
                    leading: Icon(Icons.lock_open),
                    title: Text('This capsule is not encrypted.'),
                  ),
                if (capsule.isEncrypted)
                  ListTile(
                    leading: const Icon(Icons.content_copy),
                    title: const Text('Copy a reminder note'),
                    subtitle: const Text(
                        'Copies a safe note about passphrases (without the actual passphrase).'),
                    onTap: () async {
                      const note =
                          "Reminder: If the Legacy Packet is encrypted, you'll need the passphrase I gave you separately.";
                      await Clipboard.setData(const ClipboardData(text: note));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied.')));
                    },
                  ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _share,
                  icon: const Icon(Icons.send),
                  label: Text(widget.autoOpenShareSheet
                      ? 'Sending…'
                      : 'Open share sheet'),
                ),
              ],
            ),
    );
  }
}
