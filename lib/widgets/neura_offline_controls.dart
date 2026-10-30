import 'package:flutter/material.dart';

import '../services/neura_offline_budget.dart';

class NeuraOfflineControls extends StatefulWidget {
  const NeuraOfflineControls({super.key, required this.budget});
  final NeuraOfflineBudget budget;

  @override
  State<NeuraOfflineControls> createState() => _NeuraOfflineControlsState();
}

class _NeuraOfflineControlsState extends State<NeuraOfflineControls>
    with WidgetsBindingObserver {
  late NeuraOfflineBudget _budget;
  String? _memory;
  bool _checking = false;
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    _budget = widget.budget;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      ++_serial;
      if (mounted) {
        setState(() {
          _memory = null;
          _checking = false;
        });
      }
    }
  }

  @override
  void dispose() {
    ++_serial;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check() async {
    final serial = ++_serial;
    setState(() => _checking = true);
    final value = await NeuraOfflineMemory.read();
    if (!mounted || serial != _serial) return;
    setState(() {
      _checking = false;
      _memory = value == null
          ? 'RAM check unavailable. Windows checks memory again before each reply.'
          : '${value.availableMiB} MiB available of ${value.totalMiB} MiB. '
              '${value.admitted ? 'Meets the RAM floor at this moment.' : 'Below the RAM floor. Close other apps before trying again.'} '
              'This does not verify Ollama or model readiness.';
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Offline conversation controls'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Qwen3 4B stays selected. Compact retains less recent text; '
              'it does not reduce the model’s base RAM requirement. '
              'The Windows floor is 7 GiB total and 3.5 GiB available. '
              'No downloads or cloud fallback.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<NeuraOfflineBudget>(
              initialValue: _budget,
              decoration: const InputDecoration(labelText: 'Recent context'),
              items: [
                for (final budget in NeuraOfflineBudget.values)
                  DropdownMenuItem(
                    value: budget,
                    child: Text(
                      '${budget.label} · ${budget.contextBytes} UTF-8 bytes',
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _budget = value);
              },
            ),
            TextButton(
              onPressed: _checking ? null : _check,
              child: Text(_checking ? 'Checking…' : 'Check available RAM'),
            ),
            if (_memory != null) Text(_memory!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _budget),
            child: const Text('Apply'),
          ),
        ],
      );
}
