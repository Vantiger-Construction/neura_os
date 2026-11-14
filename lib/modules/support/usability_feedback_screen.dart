import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'private_support_state.dart';
import 'support_page_shortcuts.dart';

class UsabilityFeedbackScreen extends StatefulWidget {
  const UsabilityFeedbackScreen({super.key, this.copyText});
  final Future<void> Function(String)? copyText;

  @override
  State<UsabilityFeedbackScreen> createState() =>
      _UsabilityFeedbackScreenState();
}

class _UsabilityFeedbackScreenState
    extends PrivateSupportState<UsabilityFeedbackScreen> {
  static const _tasks = [
    'Find a support activity',
    'Stop an activity',
    'Understand what is saved',
    'Find human support'
  ];
  final _answers = <String, String>{};
  final _comment = TextEditingController();
  final _preview = TextEditingController();
  bool _reviewing = false;
  bool _approved = false;
  bool _busy = false;
  String? _notice;

  @override
  void clearPrivateContent() {
    _answers.clear();
    _comment.clear();
    _preview.clear();
    _reviewing = false;
    _approved = false;
    _notice = 'Feedback draft cleared. Nothing was sent or saved.';
  }

  void _review() {
    if (!mayUse || _busy) return;
    final lines = [
      'Voluntary Neura usability feedback',
      'This describes app usability, not treatment outcomes or a clinical assessment.',
      for (final task in _tasks)
        '$task: ${_answers[task] ?? 'Not tried / skipped'}',
      '',
      'What I would change (optional):',
      _comment.text.trim()
    ];
    requestGeneration++;
    setState(() {
      _preview.text = lines.join('\n');
      _reviewing = true;
      _approved = false;
      _notice = null;
    });
  }

  Future<void> _copy() async {
    if (!mayUse ||
        _busy ||
        !_approved ||
        !_reviewing ||
        _preview.text.length > 6000) {
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
          _notice =
              'Report copied. Nothing has been sent; you decide whether to share it.';
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
    _comment.dispose();
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayedRequest = requestGeneration;
    return SupportPageShortcuts(
        child: Scaffold(
      appBar: AppBar(title: const Text('Help improve Neura'), actions: [
        IconButton(
            tooltip: 'Stop and clear feedback',
            onPressed: () => setState(invalidateDraft),
            icon: const Icon(Icons.stop_circle_outlined)),
      ]),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text(
              'Entirely optional. Skip any question or stop at any time. '
              'Please leave out names, diagnoses, contact details and private journal text. '
              'This form does not collect symptoms or monitor your wellbeing.'),
          const SizedBox(height: 12),
          if (_notice != null)
            Semantics(liveRegion: true, child: Text(_notice!)),
          if (!_reviewing) ...[
            for (final task in _tasks)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                            header: true,
                            child: Text(task,
                                style:
                                    Theme.of(context).textTheme.titleMedium)),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final answer in [
                            'Easy',
                            'Difficult',
                            'Could not do it',
                            'Not tried / skipped'
                          ])
                            ChoiceChip(
                                label: Text(answer),
                                selected: _answers[task] == answer,
                                onSelected: mayUse
                                    ? (selected) {
                                        if (!isCurrent(displayedRequest) ||
                                            _reviewing) {
                                          return;
                                        }
                                        setState(() {
                                          if (selected) {
                                            _answers[task] = answer;
                                          } else {
                                            _answers.remove(task);
                                          }
                                        });
                                      }
                                    : null),
                        ]),
                      ])),
            TextField(
                key: ValueKey('feedback-comment-$editorGeneration'),
                controller: _comment,
                enabled: mayUse,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                    labelText: 'What would make the app easier? (optional)',
                    border: OutlineInputBorder())),
            FilledButton(
                onPressed: mayUse ? _review : null,
                child: const Text('Preview feedback')),
          ] else ...[
            TextField(
                key: ValueKey('feedback-preview-$editorGeneration'),
                controller: _preview,
                minLines: 6,
                maxLines: 16,
                maxLength: 6000,
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
                    labelText: 'Editable feedback report',
                    border: OutlineInputBorder())),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title:
                    const Text('I reviewed this report and choose to copy it'),
                subtitle: const Text(
                    'Copying puts it on the system clipboard. Neura does not send or store it; copied text may remain after you leave.'),
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
                child: const Text('Copy feedback report')),
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
                child: const Text('Discard preview and edit answers')),
          ],
          TextButton(
              onPressed: () => setState(invalidateDraft),
              child: const Text('Stop and clear')),
          const Text(
              'Leaving this screen or app clears the draft. This is not an emergency contact form.'),
        ]),
      ))),
    ));
  }
}
