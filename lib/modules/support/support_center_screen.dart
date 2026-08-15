import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/neura_explain.dart';
import 'support_store.dart';
import 'support_models.dart';

class SupportCenterScreen extends StatefulWidget {
  const SupportCenterScreen({super.key});

  @override
  State<SupportCenterScreen> createState() => _SupportCenterScreenState();
}

class _SupportCenterScreenState extends State<SupportCenterScreen> {
  List<TrustedContact> _contacts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await SupportStore.instance.getAll();
    if (!mounted) return;
    setState(() {
      _contacts = list;
      _loading = false;
    });
  }

  Future<void> _addContactDialog() async {
    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    final noteC = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add trusted contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameC,
              decoration: const InputDecoration(
                  labelText: 'Name', border: OutlineInputBorder()),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneC,
              decoration: const InputDecoration(
                  labelText: 'Phone', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteC,
              decoration: const InputDecoration(
                  labelText: 'Note (optional)', border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Add')),
        ],
      ),
    );

    if (ok == true) {
      final name = nameC.text.trim();
      final phone = phoneC.text.trim();
      final note = noteC.text.trim();
      if (name.isNotEmpty && phone.isNotEmpty) {
        await SupportStore.instance.add(name: name, phone: phone, note: note);
        await _load();
      }
    }

    nameC.dispose();
    phoneC.dispose();
    noteC.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final explain = NeuraExplainSpec(
      title: 'Support Center',
      body:
          'A calm, no-drama space for grounding tools and "reach out" helpers.',
      bullets: const [
        'Calm Protocol: a 60–120 second reset you can do anywhere.',
        'Trusted Contacts are stored locally only.',
        "This is not emergency services; call local emergency numbers if you're in danger.",
      ],
      footer:
          "If you're feeling unsafe or in crisis, contact local emergency services or a crisis hotline in your country.",
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Center'),
        actions: [
          IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: () => showNeuraExplain(context, spec: explain)),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContactDialog,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add contact'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _CalmProtocolCard(),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Trusted Contacts',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (_contacts.isEmpty)
                          const Text(
                              'Add someone you trust. Neura will prep a "reach out" message you can copy.')
                        else
                          ..._contacts.map((c) => _ContactTile(
                                contact: c,
                                onDelete: () async {
                                  await SupportStore.instance.delete(c.id);
                                  await _load();
                                },
                              )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final TrustedContact contact;
  final VoidCallback onDelete;

  const _ContactTile({required this.contact, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(contact.name),
        subtitle: Text(
            '${contact.phone}${contact.note.trim().isEmpty ? '' : "\n${contact.note}"}'),
        isThreeLine: contact.note.trim().isNotEmpty,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'copy_phone') {
              await Clipboard.setData(ClipboardData(text: contact.phone));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Phone copied.')));
              }
            }
            if (v == 'copy_text') {
              final msg =
                  "Hey ${contact.name}, I could use a little support right now. If you're free, can we talk?";
              await Clipboard.setData(ClipboardData(text: msg));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message copied.')));
              }
            }
            if (v == 'delete') {
              onDelete();
            }
          },
          itemBuilder: (ctx) => const [
            PopupMenuItem(value: 'copy_phone', child: Text('Copy phone')),
            PopupMenuItem(value: 'copy_text', child: Text('Copy message')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

class _CalmProtocolCard extends StatefulWidget {
  const _CalmProtocolCard();

  @override
  State<_CalmProtocolCard> createState() => _CalmProtocolCardState();
}

class _CalmProtocolCardState extends State<_CalmProtocolCard> {
  Timer? _t;
  int _secondsLeft = 0;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _start(int seconds) {
    _t?.cancel();
    setState(() => _secondsLeft = seconds);
    _t = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        if (mounted) setState(() => _secondsLeft = 0);
      } else {
        if (mounted) setState(() => _secondsLeft -= 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final running = _secondsLeft > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.spa_outlined),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Calm Protocol',
                        style: Theme.of(context).textTheme.titleMedium)),
                if (running) Text('$_secondsLeft s'),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
                '60 seconds of "my nervous system is not the boss of me."'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => _start(60),
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('60s reset'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _start(120),
                  icon: const Icon(Icons.timer),
                  label: const Text('120s reset'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    const steps =
                        'Grounding 5-4-3-2-1:\n5 things you see\n4 things you feel\n3 things you hear\n2 things you smell\n1 thing you taste';
                    await Clipboard.setData(const ClipboardData(text: steps));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Grounding steps copied.')));
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy steps'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Breathe: in 4… out 6… (repeat).\nThen pick ONE tiny safe action.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          ],
        ),
      ),
    );
  }
}
