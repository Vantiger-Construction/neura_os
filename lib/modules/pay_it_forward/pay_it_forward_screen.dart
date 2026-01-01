import 'package:flutter/material.dart';

import '../../widgets/neura_explain.dart';
import 'goodwill_controller.dart';
import 'goodwill_models.dart';
import 'goodwill_widgets.dart';

class PayItForwardScreen extends StatefulWidget {
  const PayItForwardScreen({super.key});

  @override
  State<PayItForwardScreen> createState() => _PayItForwardScreenState();
}

class _PayItForwardScreenState extends State<PayItForwardScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await GoodwillController.instance.ensureLoaded();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _logAct() async {
    final act = await _KindnessActDialog.show(context);
    if (act == null) return;

    final increased = await GoodwillController.instance.addAct(act);
    if (!mounted) return;

    if (increased) {
      await showGoodwillCelebrationDialog(context, newStreak: GoodwillController.instance.streak.value);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logged. Kindness has been recorded by the universe.')),
      );
    }
  }

  Future<void> _showWhy() async {
    await showNeuraExplain(
      context,
      spec: const NeuraExplainSpec(
        title: 'Why Pay It Forward exists',
        body:
            'Because humans are not just productivity machines. Doing good for someone else is one of the fastest ways to unstick the brain and rebuild meaning.',
        bullets: [
          'Neura tracks *acts*, not private identity details.',
          'A streak is just encouragement — not judgment.',
          'You can delete or wipe this history anytime from Data Controls.',
        ],
        footer: 'Pro tip: tiny counts. One kind text is still kindness.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = GoodwillController.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay It Forward'),
        actions: [
          IconButton(onPressed: _showWhy, icon: const Icon(Icons.info_outline)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v != 'wipe') return;
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Wipe kindness history?'),
                  content: const Text('This deletes all Pay It Forward entries stored on this device.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Wipe')),
                  ],
                ),
              );
              if (ok == true) {
                await GoodwillController.instance.wipeAll();
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'wipe', child: Text('Wipe history')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _logAct,
        icon: const Icon(Icons.add),
        label: const Text('Log a kind act'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder<int>(
              valueListenable: c.streak,
              builder: (ctx, streak, _) {
                return ValueListenableBuilder<List<KindnessAct>>(
                  valueListenable: c.acts,
                  builder: (ctx, acts, __) {
                    final recent = List<KindnessAct>.from(acts)
                      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        GoodwillStreakBadge(streak: streak),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text('Recent acts', style: Theme.of(context).textTheme.titleMedium),
                            const Spacer(),
                            WhyChip(
                              spec: const NeuraExplainSpec(
                                title: 'Why am I seeing this list?',
                                body: 'This is your local history of kindness acts. Neura uses it to show streaks and to suggest low-effort ways to do good when you feel stuck.',
                                bullets: [
                                  'Stored on-device using SharedPreferences.',
                                  'You can delete individual acts or wipe everything.',
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (recent.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(18),
                            child: Center(child: Text('No acts logged yet. Start with something small.')),
                          )
                        else
                          ...recent.take(60).map((a) {
                            final ts = a.timestamp;
                            final when =
                                '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} '
                                '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.favorite),
                                title: Text('${a.category} • $when'),
                                subtitle: a.note.trim().isEmpty ? null : Text(a.note),
                                trailing: IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (dctx) => AlertDialog(
                                        title: const Text('Delete act?'),
                                        content: const Text('This removes it from your local history.'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancel')),
                                          FilledButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Delete')),
                                        ],
                                      ),
                                    );
                                    if (ok != true) return;

                                    await GoodwillController.instance.deleteAct(a);
                                  },
                                ),
                              ),
                            );
                          }),
                        const SizedBox(height: 90),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}

class _KindnessActDialog {
  static Future<KindnessAct?> show(BuildContext context) async {
    final category = ValueNotifier<String>('kind text');
    final note = TextEditingController();

    final result = await showDialog<KindnessAct?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Log a kind act'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<String>(
                valueListenable: category,
                builder: (ctx, v, _) {
                  return DropdownButtonFormField<String>(
                    value: v,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: const [
                      DropdownMenuItem(value: 'kind text', child: Text('Kind text')),
                      DropdownMenuItem(value: 'helped someone', child: Text('Helped someone')),
                      DropdownMenuItem(value: 'donated', child: Text('Donated')),
                      DropdownMenuItem(value: 'volunteered', child: Text('Volunteered')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (nv) {
                      if (nv == null) return;
                      category.value = nv;
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Neura stores this locally so you can track streaks. You can delete it anytime.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop(
                  KindnessAct(
                    timestamp: DateTime.now(),
                    category: category.value,
                    note: note.text.trim(),
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    note.dispose();
    category.dispose();

    return result;
  }
}
