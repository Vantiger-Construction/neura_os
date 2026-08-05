import 'package:flutter/material.dart';

import '../../core/memory/memory_graph_service.dart';

/// View/search what's actually stored in [MemoryGraphService] - the same
/// encrypted, on-device store that now backs Neura's chat recall and
/// therapy-journal reflections. Read-only aside from the reset action;
/// nothing here writes new memories.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _all = const [];
  List<Map<String, dynamic>> _filtered = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_applyFilter);
  }

  Future<void> _load() async {
    final nodes = await MemoryGraphService.I.recentNodes(limit: 500);
    if (!mounted) return;
    setState(() {
      _all = nodes;
      _filtered = nodes;
      _loading = false;
    });
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? _all
          : _all.where((n) {
              final payload = n['payload'] as Map<String, dynamic>? ?? {};
              final haystack = [
                n['type'],
                payload['text'],
                payload['promptTitle'],
              ].whereType<String>().join(' ').toLowerCase();
              return haystack.contains(query);
            }).toList();
    });
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all memory?'),
        content: const Text(
          'This permanently deletes everything Neura remembers from past '
          'conversations and reflections. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await MemoryGraphService.I.resetAll();
    await _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _label(Map<String, dynamic> node) {
    final type = node['type'] as String? ?? '';
    final payload = node['payload'] as Map<String, dynamic>? ?? {};
    if (type == 'ACTION:CHAT_MESSAGE') return 'You said: ${payload['text'] ?? ''}';
    if (type == 'SUGGESTION:CHAT_REPLY') return 'Neura said: ${payload['text'] ?? ''}';
    if (type == 'ACTION:THERAPY_REFLECTION') {
      return '${payload['promptTitle'] ?? 'Reflection'}: ${payload['text'] ?? ''}';
    }
    return type;
  }

  IconData _icon(String type) {
    if (type == 'ACTION:CHAT_MESSAGE') return Icons.person_outline;
    if (type == 'SUGGESTION:CHAT_REPLY') return Icons.smart_toy_outlined;
    if (type == 'ACTION:THERAPY_REFLECTION') return Icons.self_improvement_outlined;
    return Icons.circle_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('What Neura Remembers'),
        actions: [
          IconButton(
            tooltip: 'Clear all memory',
            onPressed: _all.isEmpty ? null : _confirmClear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search memories…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          _all.isEmpty
                              ? "Nothing remembered yet - talk to Neura or\nsave a reflection to get started."
                              : 'No matches.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final node = _filtered[i];
                          final type = node['type'] as String? ?? '';
                          return ListTile(
                            leading: Icon(_icon(type)),
                            title: Text(_label(node), maxLines: 3, overflow: TextOverflow.ellipsis),
                            subtitle: Text(node['ts']?.toString() ?? ''),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
