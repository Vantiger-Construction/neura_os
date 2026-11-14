import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../reliability/safe_boot.dart';
import 'support_center_screen.dart';
import 'support_page_shortcuts.dart';

enum SupportRegion {
  unitedStates(
      'United States',
      'Call or text 988',
      '988 Suicide & Crisis Lifeline, available 24/7.',
      'https://988lifeline.org/',
      '911'),
  canada(
      'Canada',
      'Call or text 9-8-8',
      'Canada’s Suicide Crisis Helpline, available 24/7.',
      'https://988.ca/get-help/help-right-now',
      '911'),
  ukIreland(
      'United Kingdom / Ireland',
      'Call 116 123',
      'Samaritans, available 24/7. This is a phone service.',
      'https://www.samaritans.org/how-we-can-help/contact-samaritan/talk-us-phone/',
      '999 or 112'),
  elsewhere(
      'Somewhere else',
      'Contact your local crisis service',
      'Ask a local health service for the current crisis line in your country.',
      '',
      'your local emergency number');

  const SupportRegion(
      this.label, this.contact, this.detail, this.source, this.emergency);
  final String label;
  final String contact;
  final String detail;
  final String source;
  final String emergency;
}

/// Public contacts and temporary user-edited drafts; no sending or inference.
class HumanSupportScreen extends StatefulWidget {
  const HumanSupportScreen(
      {super.key,
      this.urgentOnly = false,
      this.copyText,
      this.trustedContactsBuilder});
  final bool urgentOnly;
  final Future<void> Function(String)? copyText;
  final WidgetBuilder? trustedContactsBuilder;

  @override
  State<HumanSupportScreen> createState() => _HumanSupportScreenState();
}

class _HumanSupportScreenState extends State<HumanSupportScreen>
    with WidgetsBindingObserver {
  final _draft = TextEditingController();
  SupportRegion? _region;
  String? _notice;
  String? _proposedTemplate;
  bool _foreground = true;
  int _epoch = 0;
  int _draftGeneration = 0;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _draft.addListener(_draftChanged);
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_safetyChanged);
    SafeBoot.instance.restartRequired.addListener(_safetyChanged);
  }

  void _draftChanged() {
    _epoch++;
    if (_proposedTemplate != null || _notice != null) {
      setState(() {
        _proposedTemplate = null;
        _notice = null;
      });
    }
  }

  void _useTemplate(String text) {
    _proposedTemplate = null;
    _notice = null;
    _draft.text = text;
    setState(() {});
  }

  void _requestTemplate(String text) {
    if (!_foreground ||
        ModalRoute.isCurrentOf(context) == false ||
        SafeBoot.instance.restartRequired.value) {
      return;
    }
    if (_draft.text.trim().isEmpty || _draft.text == text) {
      _useTemplate(text);
    } else {
      setState(() => _proposedTemplate = text);
    }
  }

  Widget _replacementChoice(String proposal) {
    final epoch = _epoch;
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Replace your current draft?',
            style: Theme.of(context).textTheme.titleMedium),
        const Text(
            'Your writing stays unchanged unless you choose Replace draft.'),
        const SizedBox(height: 8),
        Text(proposal),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
              onPressed: () => setState(() => _proposedTemplate = null),
              child: const Text('Keep my writing')),
          FilledButton(
              onPressed: () {
                if (_foreground &&
                    ModalRoute.isCurrentOf(context) != false &&
                    !SafeBoot.instance.restartRequired.value &&
                    epoch == _epoch &&
                    _proposedTemplate == proposal) {
                  _useTemplate(proposal);
                }
              },
              child: const Text('Replace draft')),
        ]),
      ]),
    ));
  }

  void _clear() {
    _epoch++;
    _draftGeneration++;
    _proposedTemplate = null;
    _notice = null;
    _draft.clear();
    _notice =
        'Temporary draft cleared. Anything you already copied remains on your clipboard.';
  }

  void _safetyChanged() {
    if (mounted) setState(_clear);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.isCurrentOf(context) == false) _clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && mounted) setState(_clear);
  }

  Future<void> _copy() async {
    if (!_foreground ||
        ModalRoute.isCurrentOf(context) == false ||
        _draft.text.trim().isEmpty) {
      return;
    }
    final epoch = _epoch;
    try {
      await (widget.copyText ??
          (text) => Clipboard.setData(ClipboardData(text: text)))(_draft.text);
      if (!mounted || epoch != _epoch) return;
      setState(
          () => _notice = 'Copied to the system clipboard. Nothing was sent. '
              'Review the recipient and text before sharing.');
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() => _notice = 'Could not copy. Your draft is still here.');
    }
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_safetyChanged);
    SafeBoot.instance.restartRequired.removeListener(_safetyChanged);
    _draft.removeListener(_draftChanged);
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SupportPageShortcuts(
          child: Scaffold(
        appBar: AppBar(
            title: Text(widget.urgentOnly
                ? 'Urgent human support'
                : 'Help me reach someone')),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text('You can reach a person',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text(
                'If you or someone else is in immediate danger, contact local emergency services '
                'or go to an emergency department. Neura cannot monitor emergencies or contact help for you.'),
            const SizedBox(height: 16),
            const Text('Where are you now? (not saved)'),
            const SizedBox(height: 8),
            // Inline selection does not cover the route or clear its draft.
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final region in SupportRegion.values)
                ChoiceChip(
                  label: Text(region == SupportRegion.ukIreland
                      ? 'UK / Ireland'
                      : region.label),
                  selected: _region == region,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) => setState(() => _region = region),
                ),
            ]),
            const SizedBox(height: 12),
            if (_region case final region?)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(region.contact,
                                style: Theme.of(context).textTheme.titleLarge),
                            Text(region.detail),
                            Text('Immediate danger: ${region.emergency}.'),
                            if (region.source.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SelectableText(region.source),
                            ],
                            const SizedBox(height: 8),
                            const Text(
                                'Contact details checked 14 November 2026. Available here offline; '
                                'calling or texting uses your phone service.'),
                          ]))),
            if (!widget.urgentOnly) ...[
              const SizedBox(height: 20),
              const Text(
                  'For ongoing difficulties, a qualified health professional can help you explore '
                  'support and treatment. You can bring notes or someone you trust.'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(
                    onPressed: () => _requestTemplate(
                        'I have been having a difficult time. Would you be available to talk or check in with me?'),
                    child: const Text('Start a message')),
                OutlinedButton(
                    onPressed: () => _requestTemplate(
                        'What I have noticed:\n\nHow it affects my day:\n\n'
                        'What I would like help with:\n\nQuestions: What support options are available? '
                        'What should I do if things get worse?'),
                    child: const Text('Prepare appointment notes')),
              ]),
              const SizedBox(height: 12),
              if (_proposedTemplate case final proposal?)
                _replacementChoice(proposal),
              TextField(
                  key: ValueKey(_draftGeneration),
                  controller: _draft,
                  minLines: 5,
                  maxLines: 10,
                  maxLength: 2000,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                      labelText: 'Your draft (optional)',
                      border: OutlineInputBorder())),
              const Text(
                  'This draft stays in this screen and clears when you leave the screen or app. '
                  'Copying puts it on the system clipboard, outside Neura. Nothing is sent automatically.'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton(
                    onPressed: _copy, child: const Text('Copy reviewed draft')),
                OutlinedButton(
                    onPressed: () => setState(_clear),
                    child: const Text('Clear draft')),
              ]),
              if (_notice != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(liveRegion: true, child: Text(_notice!))),
              const SizedBox(height: 12),
              TextButton.icon(
                  onPressed: () {
                    setState(_clear);
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: widget.trustedContactsBuilder ??
                            (_) => const SupportCenterScreen()));
                  },
                  icon: const Icon(Icons.contacts_outlined),
                  label: const Text('Open my trusted contacts')),
            ],
          ]),
        ))),
      ));
}
