import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../profiles/local_profile_service.dart';
import '../services/neura_quick_notes.dart';

/// The notes the person asked Neura to take, newest first. Notes stay on
/// this device; this screen only reads, copies and deletes them.
class NeuraNotesScreen extends StatefulWidget {
  const NeuraNotesScreen({super.key, this.notes});

  /// Injected in tests; the device store otherwise.
  final NeuraQuickNotes? notes;

  @override
  State<NeuraNotesScreen> createState() => _NeuraNotesScreenState();
}

class _NeuraNotesScreenState extends State<NeuraNotesScreen> {
  NeuraQuickNotes get _store => widget.notes ?? NeuraQuickNotes.instance;
  late Future<List<NeuraQuickNote>> _notes;

  @override
  void initState() {
    super.initState();
    _notes = _load();
    _store.revision.addListener(_reload);
  }

  @override
  void dispose() {
    _store.revision.removeListener(_reload);
    super.dispose();
  }

  Future<List<NeuraQuickNote>> _load() async {
    if (LocalProfileService.instance.enabled) return const [];
    try {
      return await _store.list();
    } catch (_) {
      return const [];
    }
  }

  void _reload() {
    if (mounted) setState(() => _notes = _load());
  }

  Future<void> _delete(NeuraQuickNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this note?'),
        content: const Text('It is removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _store.delete(note.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The note could not be deleted.')),
      );
    }
  }

  Future<void> _copy(NeuraQuickNote note) async {
    await Clipboard.setData(ClipboardData(text: note.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied.')),
    );
  }

  static String _when(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final profile = LocalProfileService.instance.enabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      body: FutureBuilder<List<NeuraQuickNote>>(
        future: _notes,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final notes = snapshot.data ?? const [];
          if (profile || notes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  profile
                      ? 'Notes are not available in a profile session.'
                      : 'No notes yet. In chat, say “Neura, take a note” '
                          'followed by what to write down, or “Neura, start '
                          'taking notes” to write down a conversation.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: notes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final note = notes[index];
              final transcript = note.kind == NeuraQuickNoteKind.transcript;
              final languages =
                  note.languages.map((l) => l.nativeName).join(' · ');
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            transcript
                                ? Icons.record_voice_over_outlined
                                : Icons.sticky_note_2_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              [
                                _when(note.createdAt),
                                if (transcript) 'Conversation notes',
                                if (languages.isNotEmpty) languages,
                              ].join(' · '),
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy',
                            icon: const Icon(Icons.copy_outlined),
                            onPressed: () => _copy(note),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(note),
                          ),
                        ],
                      ),
                      SelectableText(note.text),
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
