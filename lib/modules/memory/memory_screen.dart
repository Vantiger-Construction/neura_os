import 'package:flutter/material.dart';

import '../../core/memory/memory_graph_service.dart';
import '../../encrypted_memory/companion_memory_service.dart';
import '../../encrypted_memory/encrypted_memory_session_adapter.dart';
import '../../startup/neura_prefs_cache.dart';
import '../../reliability/safe_boot.dart';

/// Explicitly authored, scoped companion notes. Opening this route does not
/// decrypt memory. Legacy histories remain deletable but are never imported.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, this.memoryService});

  final CompanionMemoryService? memoryService;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _note = TextEditingController();
  CompanionMemoryService? _memory;
  CompanionMemoryPermission? _viewPermission;
  CompanionMemoryPermission? _activePermission;
  List<EncryptedMemorySessionRecord> _records = const [];
  bool _busy = false;
  String? _status;
  int _epoch = 0;
  TextEditingController? _edit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafety);
    SafeBoot.instance.restartRequired.addListener(_onSafety);
  }

  void _onSafety() {
    if (SafeBoot.instance.safeMode.value ||
        SafeBoot.instance.restartRequired.value) {
      _clearPrivateView();
    }
  }

  void _clearPrivateView() {
    _epoch++;
    _note.clear();
    _search.clear();
    _edit?.clear();
    _activePermission?.revoke();
    _viewPermission?.revoke();
    if (mounted) setState(() => _records = const []);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clearPrivateView();
  }

  Future<CompanionMemoryService> _service() async {
    if (_memory != null) return _memory!;
    final memory = widget.memoryService ?? await CompanionMemoryService.local();
    if (!mounted) throw StateError('Memory screen closed.');
    _memory = memory;
    memory.addListener(_onRevoked);
    return memory;
  }

  void _onRevoked() {
    if (!mounted) return;
    try {
      if (_memory?.isAvailable != true) {
        _note.clear();
        _search.clear();
        throw StateError('Memory unavailable.');
      }
      _viewPermission?.requireCurrent();
    } catch (_) {
      if (_edit != null) {
        _epoch++;
        _edit!.clear();
      }
      setState(() {
        _records = const [];
        _status = 'Memory access ended. Review again to continue.';
      });
    }
  }

  Future<void> _review() async {
    if (_busy) return;
    final epoch = _epoch;
    setState(() => _busy = true);
    try {
      final memory = await _service();
      if (!mounted || epoch != _epoch) return;
      _viewPermission?.revoke();
      final permission = memory.authorize(
        CompanionMemoryUse.review,
        directUserGesture: true,
      );
      _activePermission = permission;
      final records = await memory.recall(
        permission,
        use: CompanionMemoryUse.review,
      );
      if (!mounted) return;
      permission.requireCurrent();
      _viewPermission = permission;
      setState(() {
        _records = records;
        _status = records.isEmpty ? 'No companion notes saved.' : null;
      });
    } catch (_) {
      _activePermission?.revoke();
      if (mounted) {
        setState(() {
          _records = const [];
          _status = 'Memory access was not authorized or is unavailable.';
        });
      }
    } finally {
      _activePermission = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remember() async {
    if (_busy || _note.text.trim().isEmpty) return;
    final note = _note.text.trim();
    final epoch = _epoch;
    setState(() => _busy = true);
    try {
      final memory = await _service();
      if (!mounted || epoch != _epoch) return;
      final permission = memory.authorize(
        CompanionMemoryUse.remember,
        directUserGesture: true,
      );
      _activePermission = permission;
      await memory.remember(permission, note);
      if (!mounted) return;
      setState(() {
        _note.clear();
        _status =
            'Note saved, encrypted on this device. Review to see saved notes.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _status = 'Could not confirm the save. Your draft is still here.',
        );
      }
    } finally {
      _activePermission?.revoke();
      _activePermission = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(EncryptedMemorySessionRecord record,
      {required bool forget}) async {
    if (_busy) return;
    final epoch = _epoch;
    final edit = TextEditingController(text: forget ? '' : record.value);
    _edit = edit;
    final route = DialogRoute<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(forget ? 'Forget this note?' : 'Correct this note'),
                content: forget
                    ? const Text(
                        'Delete this note from this device. Existing memory permissions will end.')
                    : TextField(
                        controller: edit,
                        maxLength: 1000,
                        decoration: const InputDecoration(
                            labelText: 'Replacement note')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(forget ? 'Forget note' : 'Save correction'))
                ]));
    final confirmed = await Navigator.of(context).push(route);
    await route.completed;
    final replacement = edit.text;
    _edit = null;
    edit.dispose();
    if (confirmed != true || !mounted || epoch != _epoch) return;
    setState(() => _busy = true);
    try {
      final memory = await _service();
      if (!mounted || epoch != _epoch) return;
      final permission = memory.authorize(
          forget ? CompanionMemoryUse.forget : CompanionMemoryUse.correct,
          directUserGesture: true);
      _activePermission = permission;
      final changed = await memory.changeNote(permission,
          recordId: record.id, replacement: forget ? null : replacement);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _records = const [];
        _status = changed
            ? 'Note ${forget ? 'forgotten' : 'corrected'}. Review to see current notes.'
            : 'That note is no longer available. Review again.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _status =
            'The change could not be confirmed. Review before retrying.');
      }
    } finally {
      _activePermission?.revoke();
      _activePermission = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all companion memory?'),
        content: const Text(
          'Permanently delete saved companion notes, legacy conversation '
          'memory and its old profile summary on this device. '
          'Your local journals and saved therapy reflections stay in their own stores.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear everything'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final memory = await _service();
      final permission = memory.authorize(
        CompanionMemoryUse.wipe,
        directUserGesture: true,
      );
      _activePermission = permission;
      await memory.wipeNotes(permission);
      await MemoryGraphService.I.resetAll();
      final prefs = NeuraPrefsCache.prefs;
      if (!await prefs.remove('neura.memory_profile.v1')) {
        throw StateError('Profile deletion failed.');
      }
      await prefs.reload();
      if (prefs.containsKey('neura.memory_profile.v1')) {
        throw StateError('Profile remains.');
      }
      if (mounted) {
        setState(() {
          _records = const [];
          _status = 'Companion memory cleared.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = 'Memory deletion could not be fully confirmed.',
        );
      }
    } finally {
      _activePermission?.revoke();
      _activePermission = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafety);
    SafeBoot.instance.restartRequired.removeListener(_onSafety);
    _memory?.removeListener(_onRevoked);
    _activePermission?.revoke();
    _viewPermission?.revoke();
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final filtered =
        _records.where((r) => r.value.toLowerCase().contains(query)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('What Neura Remembers'),
        actions: [
          IconButton(
            tooltip: 'Clear all companion memory',
            onPressed: _busy ? null : _confirmClear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text(
              'Only notes you explicitly save are used as companion memory. '
              'Chats, journals and therapy reflections are not copied here. '
              'Chat recall and any cloud request need separate approval.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 1000,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Write a companion note',
                border: OutlineInputBorder(),
              ),
            ),
            FilledButton(
              onPressed: _busy ? null : _remember,
              child: const Text('Remember this note on this device'),
            ),
            TextButton(
              onPressed: _busy ? null : _review,
              child: const Text('Review saved notes on this device'),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_status != null) Text(_status!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search reviewed notes…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, i) => ListTile(
                  leading: const Icon(Icons.note_outlined),
                  title: Text(filtered[i].value),
                  subtitle: Text('You saved this note on this device.\n'
                      '${(filtered[i].provenance.reviewedAtUtc ?? filtered[i].createdAtUtc).toLocal()}'),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Edit or forget note',
                    enabled: !_busy,
                    onSelected: (action) =>
                        _change(filtered[i], forget: action == 'forget'),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'correct', child: Text('Correct note')),
                      PopupMenuItem(
                          value: 'forget', child: Text('Forget note')),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
