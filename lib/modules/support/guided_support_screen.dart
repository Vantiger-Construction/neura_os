import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../guardrails/support_resources.dart';
import '../../reliability/safe_boot.dart';
import 'guided_support_activity.dart';
import 'guided_support_store.dart';
import 'support_center_screen.dart';

class GuidedSupportScreen extends StatefulWidget {
  const GuidedSupportScreen({super.key, this.store});

  final GuidedSupportStore? store;

  @override
  State<GuidedSupportScreen> createState() => _GuidedSupportScreenState();
}

class _GuidedSupportScreenState extends State<GuidedSupportScreen>
    with WidgetsBindingObserver {
  final _drafts = List.generate(3, (_) => TextEditingController());
  final _scroll = ScrollController();
  GuidedSupportStore get _store => widget.store ?? GuidedSupportStore.instance;
  GuidedSupportActivity? _activity;
  RememberedSupportActivity? _remembered;
  GuidedSupportFeedback? _feedback;
  int _step = 0;
  int _epoch = 0;
  bool _checkIn = false;
  bool _working = false;
  bool _active = true;
  bool _loading = true;
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafeMode);
    unawaited(_loadPreference());
  }

  Future<void> _loadPreference() async {
    final epoch = _epoch;
    try {
      final record = await _store.read();
      if (!mounted || epoch != _epoch) return;
      setState(() => _remembered = record);
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() => _notice =
          'Your remembered activity could not be opened. You can still use every activity.');
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  void _clearDrafts() {
    for (final draft in _drafts) {
      draft.clear();
    }
  }

  void _onSafeMode() {
    _epoch++;
    if (SafeBoot.instance.safeMode.value) {
      _clearDrafts();
      setState(() {
        _remembered = null;
        _feedback = null;
        _loading = false;
        _notice = 'Safe Mode: activities are available; remembering is paused.';
      });
    } else {
      unawaited(_loadPreference());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _epoch++;
    if (!_active) {
      _clearDrafts();
      setState(() {
        _feedback = null;
        _remembered = null;
        _loading = false;
        _notice = 'Temporary writing was cleared when you left the app.';
      });
    } else {
      unawaited(_loadPreference());
    }
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafeMode);
    for (final draft in _drafts) {
      draft.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _choose(GuidedSupportActivity? activity) {
    _epoch++;
    _clearDrafts();
    FocusScope.of(context).unfocus();
    setState(() {
      _activity = activity;
      _step = 0;
      _checkIn = false;
      _feedback = null;
      _notice = null;
      _loading = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (activity == null) unawaited(_loadPreference());
  }

  void _advance() {
    FocusScope.of(context).unfocus();
    setState(() {
      if (_step + 1 < _activity!.steps.length) {
        _step++;
      } else {
        _clearDrafts();
        _checkIn = true;
      }
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _remember() async {
    final activity = _activity;
    if (_working ||
        activity == null ||
        _feedback != GuidedSupportFeedback.helped ||
        !_active ||
        SafeBoot.instance.safeMode.value) {
      return;
    }
    final epoch = _epoch;
    setState(() => _working = true);
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remember ${activity.label.toLowerCase()}?'),
          scrollable: true,
          content: Text(
            'Save “${activity.label} helped” and the time you agreed, encrypted '
            'on this device. Neura may suggest this activity when you open '
            'Help me through this again. Your writing is not saved.\n\n'
            'This replaces any previous activity preference. You can inspect, '
            'copy or forget it here at any time.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remember activity')),
          ],
        ),
      );
      bool stillApproved() =>
          mounted &&
          _active &&
          epoch == _epoch &&
          !SafeBoot.instance.safeMode.value &&
          (ModalRoute.of(context)?.isCurrent ?? false);
      if (approved != true || !stillApproved()) return;
      final record = await _store.rememberAfterConfirmation(activity,
          stillApproved: stillApproved);
      if (!stillApproved()) return;
      setState(() {
        _remembered = record;
        _notice =
            'Activity remembered on this device. Your writing was not saved.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _notice =
            'Remembering did not complete. You can continue without saving.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _forget() async {
    if (_working) return;
    _epoch++;
    setState(() => _working = true);
    try {
      await _store.forget();
      if (!mounted) return;
      setState(() {
        _remembered = null;
        _notice = 'Remembered activity forgotten.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _notice =
            'Could not verify deletion. Please try Forget activity again.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _managePreference() async {
    final record = _remembered;
    final epoch = _epoch;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remembered activity'),
        content: SingleChildScrollView(
            child: Text(record == null
                ? 'No activity preference is available. If saved data could not be '
                    'opened, you can still remove it with Forget activity.'
                : '${record.activity.label} helped.\n\n'
                    'You agreed on ${record.confirmedAtUtc.toLocal()}.\n'
                    'Used only to offer an activity in Help me through this. '
                    'No writing or check-in history is stored.\n\n'
                    'Copy preference places these details on your clipboard.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'forget'),
              child: const Text('Forget activity')),
          if (record != null)
            TextButton(
                onPressed: () => Navigator.pop(context, 'copy'),
                child: const Text('Copy preference')),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'forget') await _forget();
    if (action == 'copy' &&
        record != null &&
        _active &&
        epoch == _epoch &&
        !SafeBoot.instance.safeMode.value) {
      try {
        await Clipboard.setData(ClipboardData(text: record.exportText()));
        if (mounted) {
          setState(() => _notice = 'Preference copied to your clipboard.');
        }
      } catch (_) {
        if (mounted) {
          setState(() => _notice = 'Preference could not be copied.');
        }
      }
    }
  }

  Future<void> _humanSupport() async {
    _epoch++;
    _clearDrafts();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reach a person'),
        content: Text('You can contact someone you trust.\n\n'
            '${SupportResources.forLocale(Localizations.localeOf(context).toString())}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(this.context).push(MaterialPageRoute<void>(
                    builder: (_) => const SupportCenterScreen()));
              },
              child: const Text('Trusted contacts')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activity = _activity;
    final remembered = _remembered;
    final safeMode = SafeBoot.instance.safeMode.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Help me through this'), actions: [
        IconButton(
            tooltip: 'Remembered activity',
            onPressed: _working ? null : _managePreference,
            icon: const Icon(Icons.bookmark_outline)),
      ]),
      body: SafeArea(
          child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(20),
              children: [
                if (_notice != null) ...[
                  Semantics(liveRegion: true, child: Text(_notice!)),
                  const SizedBox(height: 16),
                ],
                if (activity == null) ...[
                  Text('What would help right now?',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  const Text(
                      'Take a quiet moment to write, settle, or make a small plan. '
                      'Try a minute or two, and stop whenever you like.'),
                  const SizedBox(height: 16),
                  if (remembered != null && !safeMode)
                    Card(
                        child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'You asked Neura to remember that ${remembered.activity.label.toLowerCase()} helped.'),
                          const SizedBox(height: 8),
                          OutlinedButton(
                              onPressed: () => _choose(remembered.activity),
                              child: Text(
                                  'Try ${remembered.activity.label.toLowerCase()} again')),
                        ],
                      ),
                    )),
                  for (final choice in GuidedSupportActivity.values)
                    Card(
                        child: ListTile(
                      title: Text(choice.label),
                      subtitle: Text(choice.description),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _choose(choice),
                    )),
                  const SizedBox(height: 12),
                  const Text(
                      'These activities work without an internet connection. '
                      'Temporary writing clears when you finish, switch activities, '
                      'leave this screen or leave the app.'),
                ] else if (!_checkIn) ...[
                  Text(activity.label,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                      'Step ${_step + 1} of ${activity.steps.length} · At your pace'),
                  const SizedBox(height: 20),
                  Semantics(
                      header: true,
                      liveRegion: true,
                      child: Text(activity.steps[_step].title,
                          style: Theme.of(context).textTheme.headlineSmall)),
                  const SizedBox(height: 12),
                  Text(activity.steps[_step].body),
                  if (activity.steps[_step].prompt != null) ...[
                    const SizedBox(height: 20),
                    TextField(
                      key: ValueKey('${activity.name}_$_step'),
                      controller: _drafts[_step],
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 2000,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                          labelText: activity.steps[_step].prompt,
                          alignLabelWithHint: true,
                          border: const OutlineInputBorder()),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Wrap(spacing: 12, runSpacing: 8, children: [
                    if (_step > 0)
                      OutlinedButton(
                          onPressed: () => setState(() => _step--),
                          child: const Text('Previous step')),
                    FilledButton(
                        onPressed: _advance,
                        child: Text(_step + 1 == activity.steps.length
                            ? 'Check in (optional)'
                            : 'Next step')),
                  ]),
                  TextButton(
                      onPressed: () => _choose(null),
                      child: const Text('Finish without check-in')),
                ] else ...[
                  Text('How was that for you?',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  const Text(
                      'Any answer is okay. This check-in is optional and is not saved.'),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final feedback in GuidedSupportFeedback.values)
                      ChoiceChip(
                        label: Text(feedback.label),
                        selected: _feedback == feedback,
                        onSelected: _working
                            ? null
                            : (_) => setState(() => _feedback = feedback),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  if (_feedback == GuidedSupportFeedback.helped && !safeMode)
                    FilledButton(
                        onPressed: _working ? null : _remember,
                        child: const Text('Remember what helped…')),
                  if (_feedback == GuidedSupportFeedback.worse)
                    const Text(
                        'Let\'s stop this activity. You can try a different kind of support, '
                        'take a break, or reach someone you trust.'),
                  if (_feedback == GuidedSupportFeedback.same ||
                      _feedback == GuidedSupportFeedback.unsure)
                    const Text(
                        'You do not have to make this work. You can leave it here or try something else.'),
                  TextButton(
                      onPressed: _working ? null : () => _choose(null),
                      child: const Text('Done')),
                ],
                if (activity != null)
                  TextButton(
                      onPressed: _working ? null : () => _choose(null),
                      child: const Text('Choose another activity')),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                    onPressed: _working ? null : _humanSupport,
                    icon: const Icon(Icons.people_outline),
                    label: const Text('Reach a person')),
                if (_loading)
                  const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('Checking for a remembered activity…')),
              ]),
        ),
      )),
    );
  }
}
