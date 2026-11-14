import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../mood/mood_models.dart';
import '../mood/mood_store.dart';
import 'appointment_summary.dart';
import 'private_support_state.dart';
import 'support_page_shortcuts.dart';

class AppointmentPrepScreen extends StatefulWidget {
  const AppointmentPrepScreen({super.key, this.load, this.copyText, this.now});
  final Future<List<MoodEntry>> Function()? load;
  final Future<void> Function(String)? copyText;
  final DateTime Function()? now;

  @override
  State<AppointmentPrepScreen> createState() => _AppointmentPrepScreenState();
}

class _AppointmentPrepScreenState
    extends PrivateSupportState<AppointmentPrepScreen> {
  final _questions = TextEditingController();
  final _preview = TextEditingController();
  List<MoodEntry> _entries = [];
  final _selected = <int>{};
  bool _includeNotes = false;
  bool _reviewing = false;
  bool _approved = false;
  bool _busy = false;
  String? _notice;

  @override
  void clearPrivateContent() {
    _questions.clear();
    _preview.clear();
    _entries = [];
    _selected.clear();
    _includeNotes = false;
    _reviewing = false;
    _approved = false;
    _notice = 'Temporary appointment notes cleared. Nothing was sent or saved.';
  }

  Future<void> _load() async {
    if (!mayReadSaved || _busy) return;
    final request = ++requestGeneration;
    setState(() {
      _busy = true;
      _entries = [];
      _selected.clear();
      _notice = null;
    });
    try {
      final entries = await (widget.load ?? MoodStore.instance.getAll)()
          .timeout(const Duration(seconds: 8));
      if (!isCurrent(request) || !mayReadSaved) return;
      final now = (widget.now ?? DateTime.now)();
      final valid = entries
          .where((e) =>
              !e.timestamp.isAfter(now) &&
              e.mood0to10 >= 0 &&
              e.mood0to10 <= 10)
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      setState(() {
        _entries = valid.take(30).toList();
        _notice = _entries.isEmpty
            ? 'No saved check-ins available. You can still prepare questions.'
            : null;
      });
    } catch (_) {
      if (isCurrent(request)) {
        setState(() => _notice =
            'Check-ins could not be opened. You can still prepare questions.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _review() {
    if (!mayUse || _busy) return;
    try {
      final text = appointmentSummary(
          selected: [for (final i in _selected.toList()..sort()) _entries[i]],
          questions: _questions.text,
          includeNotes: _includeNotes);
      requestGeneration++;
      setState(() {
        _preview.text = text;
        _reviewing = true;
        _approved = false;
        _notice = null;
      });
    } on FormatException catch (error) {
      setState(() => _notice = error.message);
    }
  }

  Future<void> _copy() async {
    if (!mayUse ||
        _busy ||
        !_approved ||
        !_reviewing ||
        _preview.text.length > 12000) {
      return;
    }
    final request = requestGeneration;
    final text = _preview.text;
    setState(() => _busy = true);
    try {
      await (widget.copyText ??
          (text) => Clipboard.setData(ClipboardData(text: text)))(text);
      if (isCurrent(request)) {
        setState(() {
          _approved = false;
          _notice = 'Summary copied. You choose where to paste it.';
        });
      }
    } catch (_) {
      if (isCurrent(request)) {
        setState(
            () => _notice = 'Copy did not complete. Your draft is still here.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _questions.dispose();
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayedRequest = requestGeneration;
    return SupportPageShortcuts(
        child: Scaffold(
      appBar: AppBar(title: const Text('Prepare for an appointment'), actions: [
        IconButton(
            tooltip: 'Stop and clear appointment notes',
            onPressed: () => setState(invalidateDraft),
            icon: const Icon(Icons.stop_circle_outlined)),
      ]),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Make notes for a conversation with a professional. '
              'Only the check-ins you select are included. No journal is opened and no clinic is contacted.'),
          const SizedBox(height: 12),
          if (_notice != null)
            Semantics(liveRegion: true, child: Text(_notice!)),
          if (!_reviewing) ...[
            TextField(
                key: ValueKey('appointment-questions-$editorGeneration'),
                controller: _questions,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                enabled: mayUse && !_busy,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                    labelText: 'Questions or topics (optional)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: mayReadSaved && !_busy ? _load : null,
                child: Text(
                    _busy ? 'Opening…' : 'Choose saved check-ins (optional)')),
            if (_entries.isNotEmpty) ...[
              const Text(
                  'Choose up to ten of your latest thirty check-ins. None are selected automatically.'),
              for (var i = 0; i < _entries.length; i++)
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        '${_entries[i].timestamp.toLocal()} · Mood ${_entries[i].mood0to10}/10'),
                    value: _selected.contains(i),
                    onChanged: !mayUse ||
                            _busy ||
                            (_selected.length >= 10 && !_selected.contains(i))
                        ? null
                        : (value) {
                            if (!isCurrent(displayedRequest) || _reviewing) {
                              return;
                            }
                            setState(() {
                              if (value == true) {
                                _selected.add(i);
                              } else {
                                _selected.remove(i);
                              }
                            });
                          }),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include notes from my selected check-ins'),
                  subtitle: const Text(
                      'Optional. At most 500 characters from each note; shortened notes are marked.'),
                  value: _includeNotes,
                  onChanged: !mayUse || _busy
                      ? null
                      : (v) {
                          if (isCurrent(displayedRequest) && !_reviewing) {
                            setState(() => _includeNotes = v ?? false);
                          }
                        }),
            ],
            FilledButton(
                onPressed: mayUse && !_busy ? _review : null,
                child: const Text('Review my summary')),
          ] else ...[
            const Text(
                'Review and edit every part before copying. Copied text leaves Neura and may remain in your clipboard after this screen closes.'),
            const SizedBox(height: 12),
            TextField(
                key: ValueKey('appointment-preview-$editorGeneration'),
                controller: _preview,
                minLines: 8,
                maxLines: 18,
                maxLength: 12000,
                enabled: mayUse && !_busy,
                enableSuggestions: false,
                autocorrect: false,
                onChanged: (_) {
                  requestGeneration++;
                  setState(() {
                    _approved = false;
                    _notice = null;
                  });
                },
                decoration: const InputDecoration(
                    labelText: 'Editable summary',
                    border: OutlineInputBorder())),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title:
                    const Text('I reviewed this summary and choose to copy it'),
                value: _approved,
                onChanged: mayUse && !_busy
                    ? (v) {
                        if (isCurrent(displayedRequest) && _reviewing) {
                          setState(() => _approved = v ?? false);
                        }
                      }
                    : null),
            FilledButton(
                onPressed: mayUse && _approved && !_busy ? _copy : null,
                child: const Text('Copy my summary')),
            TextButton(
                onPressed: mayUse && !_busy
                    ? () => setState(() {
                          requestGeneration++;
                          editorGeneration++;
                          _preview.clear();
                          _reviewing = false;
                          _approved = false;
                          _notice = null;
                        })
                    : null,
                child: const Text('Discard preview and change selection')),
          ],
          TextButton(
              onPressed: () => setState(invalidateDraft),
              child: const Text('Stop and clear')),
          const Text(
              'These notes are temporary. Leaving this screen or app clears them; nothing resumes or sends automatically.'),
        ]),
      ))),
    ));
  }
}
