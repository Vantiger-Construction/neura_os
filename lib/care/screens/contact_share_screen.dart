import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../modules/mood/mood_models.dart';
import '../../modules/mood/mood_store.dart';
import '../models/contact_share_record.dart';
import '../models/trusted_contact.dart';
import '../services/contact_share_service.dart';

/// Lets the user hand a bounded mood-trend summary to one trusted contact,
/// and shows the local history of past shares for that contact.
///
/// Every share requires an explicit confirmation naming exactly what will
/// leave the device -- only dates and 0-10 mood scores, never notes or any
/// other Neura content -- and delivery goes through the OS share sheet the
/// user already controls. Neura never sends anything on its own.
class ContactShareScreen extends StatefulWidget {
  const ContactShareScreen({super.key, required this.contact});

  final TrustedContact contact;

  @override
  State<ContactShareScreen> createState() => _ContactShareScreenState();
}

enum _ShareWindow { week, month, quarter }

extension on _ShareWindow {
  Duration get span => switch (this) {
        _ShareWindow.week => const Duration(days: 7),
        _ShareWindow.month => const Duration(days: 30),
        _ShareWindow.quarter => const Duration(days: 90),
      };

  String get label => switch (this) {
        _ShareWindow.week => 'Last 7 days',
        _ShareWindow.month => 'Last 30 days',
        _ShareWindow.quarter => 'Last 90 days',
      };
}

class _ContactShareScreenState extends State<ContactShareScreen> {
  final _shareService = ContactShareService.instance;
  _ShareWindow _window = _ShareWindow.month;
  bool _loading = true;
  bool _sharing = false;
  List<ContactShareRecord> _history = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _shareService.load();
    if (!mounted) return;
    setState(() {
      _history = _shareService.sharesForContact(widget.contact.id);
      _loading = false;
    });
  }

  Future<List<MoodEntry>> _entriesInWindow(DateTime start, DateTime end) async {
    final all = await MoodStore.instance.getAll();
    return all
        .where(
          (entry) =>
              !entry.timestamp.isBefore(start) && !entry.timestamp.isAfter(end),
        )
        .toList(growable: false);
  }

  Future<void> _startShare() async {
    final now = DateTime.now();
    final start = now.subtract(_window.span);
    final entries = await _entriesInWindow(start, now);
    if (!mounted) return;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No mood check-ins in this window yet.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Share with ${widget.contact.name}?'),
        content: Text(
          'This will share ${entries.length} mood check-in'
          '${entries.length == 1 ? '' : 's'} from ${_window.label.toLowerCase()} '
          'as dates and 0-10 scores only. Notes, journal text, and everything '
          'else in Neura stay on this device.\n\n'
          'You\'ll choose how to send it next (message, email, etc.) -- '
          'Neura does not send anything on its own.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sharing = true);
    try {
      final summary = entries
          .map(
            (entry) =>
                '${entry.timestamp.toLocal().toIso8601String().split('T').first}: '
                'mood ${entry.mood0to10}/10',
          )
          .join('\n');
      final text = 'Mood trend shared from Neura '
          '(${_window.label.toLowerCase()}, ${entries.length} check-ins):\n\n'
          '$summary';
      await Share.share(text, subject: 'Mood trend from Neura');
      await _shareService.recordShare(
        contactId: widget.contact.id,
        rangeStart: start,
        rangeEnd: now,
        entryCount: entries.length,
      );
      if (!mounted) return;
      await _load();
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _removeFromHistory(ContactShareRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from history?'),
        content: const Text(
          'This only forgets that Neura recorded the share. It cannot recall '
          'a summary that has already been sent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _shareService.removeFromHistory(record.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Share with ${widget.contact.name}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share mood trend',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Only dates and 0-10 mood scores are ever included. '
                          'Notes and every other part of Neura stay private.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<_ShareWindow>(
                          segments: _ShareWindow.values
                              .map(
                                (window) => ButtonSegment(
                                  value: window,
                                  label: Text(window.label),
                                ),
                              )
                              .toList(growable: false),
                          selected: {_window},
                          onSelectionChanged: (selection) =>
                              setState(() => _window = selection.first),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _sharing ? null : _startShare,
                          icon: const Icon(Icons.ios_share),
                          label: Text(_sharing ? 'Preparing...' : 'Share'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Shared history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                if (_history.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.history),
                      title: Text('No shares yet'),
                      subtitle: Text(
                        'Shares with this contact will be listed here.',
                      ),
                    ),
                  )
                else
                  ..._history.map(
                    (record) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.ios_share),
                        title: Text(
                          '${record.entryCount} check-in'
                          '${record.entryCount == 1 ? '' : 's'} shared',
                        ),
                        subtitle: Text(
                          '${_formatDate(record.rangeStart)} - '
                          '${_formatDate(record.rangeEnd)} • '
                          'sent ${_formatDate(record.sharedAt)}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove from history',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => unawaited(
                            _removeFromHistory(record),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day}/${local.year}';
  }
}
