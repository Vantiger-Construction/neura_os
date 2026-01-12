import 'package:flutter/material.dart';

import 'legacy_deadman_service.dart';
import 'legacy_vault_service.dart';
import 'models/legacy_capsule.dart';

class LegacyGuardScreen extends StatefulWidget {
  const LegacyGuardScreen({super.key});

  @override
  State<LegacyGuardScreen> createState() => _LegacyGuardScreenState();
}

class _LegacyGuardScreenState extends State<LegacyGuardScreen> {
  bool _loading = true;
  LegacyDeadmanSettings _settings = LegacyDeadmanSettings.defaults();
  List<LegacyCapsule> _capsules = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await LegacyDeadmanService.instance.load();
    final caps = await LegacyVaultService.instance.listCapsules();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _capsules = caps;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    await LegacyDeadmanService.instance.save(_settings);
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Legacy Guard saved.')));
  }

  Future<void> _checkInNow() async {
    await LegacyDeadmanService.instance.markCheckedInNow();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check‑in recorded.')));
  }

  List<LegacyCapsule> get _deliverables {
    // Prefer explicit selection, but show deliverables list anyway.
    return _capsules.where((c) => c.deliveryEnabled && c.deliveryTrigger == 'deadman').toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Legacy Guard'),
        actions: [
          IconButton(tooltip: 'Save', onPressed: _loading ? null : _save, icon: const Icon(Icons.save)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  value: _settings.enabled,
                  onChanged: (v) => setState(() => _settings = _settings.copyWith(enabled: v)),
                  title: const Text('Enable Legacy Guard'),
                  subtitle: const Text('If you stop checking in, Neura will offer to prepare delivery packets.'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  title: const Text('Last check‑in'),
                  subtitle: Text(_settings.lastCheckInAt.toLocal().toString()),
                  trailing: OutlinedButton.icon(
                    onPressed: _checkInNow,
                    icon: const Icon(Icons.verified),
                    label: const Text('Check in'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _settings.checkInIntervalDays.toString(),
                        decoration: const InputDecoration(labelText: 'Check‑in interval (days)'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => setState(() => _settings = _settings.copyWith(checkInIntervalDays: int.tryParse(v) ?? 30)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: _settings.graceDays.toString(),
                        decoration: const InputDecoration(labelText: 'Grace period (days)'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => setState(() => _settings = _settings.copyWith(graceDays: int.tryParse(v) ?? 7)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Capsules to release', style: Theme.of(context).textTheme.titleMedium),
                Text(
                  'Pick which capsules are included when Legacy Guard triggers. If you leave this empty, Neura will use capsules marked Delivery → Legacy Guard.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (_capsules.isEmpty)
                  const Text('No capsules yet.')
                else
                  ..._capsules.map((c) {
                    final sel = _settings.capsuleIdsToRelease.contains(c.id);
                    return CheckboxListTile(
                      value: sel,
                      onChanged: (v) {
                        final set = {..._settings.capsuleIdsToRelease};
                        if (v == true) {
                          set.add(c.id);
                        } else {
                          set.remove(c.id);
                        }
                        setState(() => _settings = _settings.copyWith(capsuleIdsToRelease: set.toList()));
                      },
                      title: Text(c.title.isEmpty ? '(Untitled)' : c.title),
                      subtitle: Text(
                        '${c.deliveryEnabled ? 'Delivery: ${c.deliveryTrigger} • ${c.deliveryFormat}' : 'Delivery: off'}'
                        '${c.unlockAt == null ? '' : ' • Unlock: ${c.unlockAt!.toLocal().toString().substring(0, 16)}'}',
                      ),
                    );
                  }),
                const SizedBox(height: 16),
                if (_deliverables.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Tip: You have ${_deliverables.length} capsules already marked for Legacy Guard.
To auto-include them, simply clear the checkbox selections above.',
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
