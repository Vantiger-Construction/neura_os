import 'package:flutter/material.dart';

import '../../services/neura_worry_parking.dart';

/// Worry time: the parked worries come back to be sorted, one at a time if
/// the user likes: a small step, let it go, or keep it for later.
class NeuraWorryTimeScreen extends StatefulWidget {
  const NeuraWorryTimeScreen({super.key, this.parking});

  final NeuraWorryParking? parking;

  @override
  State<NeuraWorryTimeScreen> createState() => _NeuraWorryTimeScreenState();
}

class _NeuraWorryTimeScreenState extends State<NeuraWorryTimeScreen> {
  NeuraWorryParking get _parking =>
      widget.parking ?? NeuraWorryParking.instance;
  List<ParkedWorry>? _worries;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final worries = await _parking.list();
      if (mounted) setState(() => _worries = worries);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _act(Future<void> Function() action, String done) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('That could not be saved on this device.'),
        ));
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    await _load();
  }

  Future<void> _smallStep(ParkedWorry worry) async {
    final controller = TextEditingController(text: worry.step ?? '');
    final step = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("What's one small step?"),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: NeuraWorryParking.maxLength,
          decoration: const InputDecoration(
            hintText: 'Something you could do in ten minutes',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save step'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (step == null || step.trim().isEmpty) return;
    await _act(() => _parking.addStep(worry.id, step), 'Step saved.');
  }

  Future<void> _pickHour() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _parking.hour, minute: 0),
      helpText: 'Worry time starts at',
    );
    if (picked == null) return;
    await _parking.setHour(picked.hour);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final worries = _worries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worry time'),
        actions: [
          TextButton.icon(
            onPressed: _pickHour,
            icon: const Icon(Icons.schedule),
            label: Text(
              MaterialLocalizations.of(context).formatTimeOfDay(
                TimeOfDay(hour: _parking.hour, minute: 0),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _failed
            ? const Center(child: Text('Parked worries could not be read.'))
            : worries == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'During the day, type or say "park it: ..." to set a '
                        "worry aside. At worry time, sort each one. It's "
                        'okay to let some go.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      if (worries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(child: Text('Nothing is parked.')),
                        ),
                      for (final worry in worries)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(
                                  worry.text,
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Parked '
                                  '${MaterialLocalizations.of(context).formatMediumDate(worry.parkedAt)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                if (worry.step != null) ...[
                                  const SizedBox(height: 8),
                                  Text('Next step: ${worry.step}'),
                                ],
                                const SizedBox(height: 8),
                                Wrap(spacing: 8, runSpacing: 4, children: [
                                  OutlinedButton(
                                    onPressed: () => _smallStep(worry),
                                    child: const Text('Small step'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _act(
                                      () => _parking.letGo(worry.id),
                                      'Let go.',
                                    ),
                                    child: const Text('Let it go'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _act(
                                      () => _parking.keepForLater(worry.id),
                                      'Back at the next worry time.',
                                    ),
                                    child: const Text('Keep for later'),
                                  ),
                                ]),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
