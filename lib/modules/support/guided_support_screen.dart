import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../reliability/safe_boot.dart';
import 'guided_support_activity.dart';
import 'guided_support_store.dart';
import 'human_support_screen.dart';

class GuidedSupportScreen extends StatefulWidget {
  const GuidedSupportScreen({super.key, this.store, this.initialActivity});

  final GuidedSupportStore? store;
  final GuidedSupportActivity? initialActivity;

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
  SupportSuggestionChoices? _choices;
  bool _suggestionRequested = false;
  GuidedSupportFeedback? _feedback;
  int _step = 0;
  int _epoch = 0;
  int _draftGeneration = 0;
  bool _checkIn = false;
  bool _working = false;
  bool _active = true;
  bool _visible = true;
  bool _loading = false;
  bool _preferenceHidden = false;
  ValueNotifier<bool>? _dialogGate;
  String? _notice;

  bool get _privateAvailable =>
      _active &&
      !SafeBoot.instance.safeMode.value &&
      !SafeBoot.instance.restartRequired.value;

  bool _currentRequest(int epoch) =>
      mounted &&
      _active &&
      epoch == _epoch &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  String get _safetyNotice => SafeBoot.instance.restartRequired.value
      ? 'Restart Neura before opening or remembering saved activity preferences. '
          'Manual activities are still available.'
      : SafeBoot.instance.safeMode.value
          ? 'Safe Mode: activities are available; remembering is paused.'
          : 'Private support information is hidden. You can still use every activity.';

  @override
  void initState() {
    super.initState();
    _activity = widget.initialActivity;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _active = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafety);
    SafeBoot.instance.restartRequired.addListener(_onSafety);
    if (_privateAvailable) {
      unawaited(_loadPreference());
    } else {
      _invalidateSession(_safetyNotice);
    }
  }

  Future<void> _loadPreference() async {
    if (!_privateAvailable || !_visible || _loading) return;
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _preferenceHidden = false;
      _notice = null;
    });
    try {
      final choices = await _store.readChoices();
      if (!_currentRequest(epoch) || !_privateAvailable) return;
      setState(() => _choices = choices);
      if (choices.onlyWhenAsked && !requested) return;
      final record = await _store.read();
      if (!_currentRequest(epoch) || !_privateAvailable) return;
      setState(() => _remembered = record);
    } catch (_) {
      if (!_currentRequest(epoch) || !_privateAvailable) return;
      setState(() => _notice =
          'Your remembered activity could not be opened. You can still use every activity.');
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  void _clearDrafts() {
    _draftGeneration++;
    for (final draft in _drafts) {
      draft.clear();
    }
  }

  void _invalidateSession(String notice) {
    _epoch++;
    _dialogGate?.value = false;
    _clearDrafts();
    _remembered = null;
    _feedback = null;
    _loading = false;
    _preferenceHidden = true;
    _notice = notice;
  }

  void _onSafety() {
    if (mounted) setState(() => _invalidateSession(_safetyNotice));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    if (_visible && !visible && _dialogGate == null) {
      _invalidateSession(
          'Temporary writing was cleared when you left this screen.');
    }
    _visible = visible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _active = state == AppLifecycleState.resumed;
      if (!_active) {
        _invalidateSession(
            'Temporary writing was cleared when you left the app.');
      }
    });
  }

  @override
  void dispose() {
    _epoch++;
    _dialogGate?.value = false;
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafety);
    SafeBoot.instance.restartRequired.removeListener(_onSafety);
    for (final draft in _drafts) {
      draft.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<T?> _privateDialog<T>(WidgetBuilder builder) async {
    if (_dialogGate != null || !_currentRequest(_epoch)) return null;
    final gate = ValueNotifier(true);
    _dialogGate = gate;
    var covered = false;
    try {
      final result = await showDialog<T>(
        context: context,
        builder: (_) => ValueListenableBuilder<bool>(
          valueListenable: gate,
          builder: (context, allowed, _) {
            final route = ModalRoute.of(context);
            // A normal close also stops being current; only a covering route
            // revokes this request here. Lifecycle/safety changes use the gate.
            if (ModalRoute.isCurrentOf(context) == false &&
                route?.isActive == true &&
                route?.animation?.status != AnimationStatus.reverse &&
                !covered) {
              covered = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && identical(_dialogGate, gate) && gate.value) {
                  setState(() => _invalidateSession(
                      'Private support information was hidden when you left the request.'));
                }
              });
            }
            if (!allowed || covered) {
              return AlertDialog(
                title: const Text('Request expired'),
                content: const Text(
                    'This request is no longer active. Close it and start again when you are ready.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close')),
                ],
              );
            }
            return builder(context);
          },
        ),
      );
      return gate.value && !covered ? result : null;
    } finally {
      if (identical(_dialogGate, gate)) _dialogGate = null;
      gate.dispose();
    }
  }

  void _choose(GuidedSupportActivity? activity) {
    if (!_currentRequest(_epoch)) return;
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
    if (activity == null && !_preferenceHidden) unawaited(_loadPreference());
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
        !_privateAvailable ||
        !_currentRequest(_epoch)) {
      return;
    }
    final epoch = _epoch;
    setState(() => _working = true);
    try {
      final approved = await _privateDialog<bool>(
        (context) => AlertDialog(
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
      bool stillApproved() => _currentRequest(epoch) && _privateAvailable;
      if (approved != true || !stillApproved()) return;
      final record = await _store.rememberAfterConfirmation(activity,
          stillApproved: stillApproved);
      if (!stillApproved()) return;
      setState(() {
        _remembered = record;
        _preferenceHidden = false;
        _notice =
            'Activity remembered on this device. Your writing was not saved.';
      });
    } catch (_) {
      if (_currentRequest(epoch) && _privateAvailable) {
        setState(() => _notice =
            'Remembering did not complete. You can continue without saving.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _forget() async {
    if (_working || !_currentRequest(_epoch)) return;
    final epoch = ++_epoch;
    setState(() => _working = true);
    try {
      await _store.forget();
      if (!_currentRequest(epoch)) return;
      setState(() {
        _remembered = null;
        _preferenceHidden = false;
        _notice = 'Remembered activity forgotten.';
      });
    } catch (_) {
      if (_currentRequest(epoch)) {
        setState(() => _notice =
            'Could not verify deletion. Please try Forget activity again.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _managePreference() async {
    if (_working || !_currentRequest(_epoch)) return;
    final record = _privateAvailable ? _remembered : null;
    final epoch = _epoch;
    final action = await _privateDialog<String>(
      (context) => AlertDialog(
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
    if (!_currentRequest(epoch)) return;
    if (action == 'forget') await _forget();
    if (action == 'copy' && record != null && _privateAvailable) {
      try {
        await Clipboard.setData(ClipboardData(text: record.exportText()));
        if (_currentRequest(epoch) && _privateAvailable) {
          setState(() => _notice = 'Preference copied to your clipboard.');
        }
      } catch (_) {
        if (_currentRequest(epoch) && _privateAvailable) {
          setState(() => _notice = 'Preference could not be copied.');
        }
      }
    }
  }

  Future<void> _humanSupport() async {
    if (!_currentRequest(_epoch)) return;
    setState(() => _invalidateSession(
        'Temporary writing was cleared when you left this screen.'));
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const HumanSupportScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final activity = _activity;
    final remembered = _remembered;
    return Scaffold(
      appBar: AppBar(title: const Text('Help me through this'), actions: [
        if (activity != null)
          IconButton(
              tooltip: 'Stop activity',
              onPressed: () => _choose(null),
              icon: const Icon(Icons.stop_circle_outlined)),
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
                  if (_preferenceHidden && _privateAvailable && !_loading)
                    OutlinedButton(
                        onPressed: _loadPreference,
                        child: const Text('Show remembered activity')),
                  if (remembered != null && _privateAvailable)
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
                      key: ValueKey(
                          '${activity.name}_${_step}_$_draftGeneration'),
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
                  if (_feedback == GuidedSupportFeedback.helped &&
                      _privateAvailable)
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
                TextButton.icon(
                    onPressed: _working
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    SupportSuggestionScreen(store: _store))),
                    icon: const Icon(Icons.tune),
                    label: const Text('Suggestion choices')),
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
    ));
  }
}
