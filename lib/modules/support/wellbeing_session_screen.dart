import 'dart:async';

import 'package:flutter/material.dart';

import '../../reliability/safe_boot.dart';

/// Session-only tools. No persistence, OS notifications, audio or background work.
class WellbeingSessionScreen extends StatefulWidget {
  const WellbeingSessionScreen(
      {super.key, this.reminder = false, this.now, this.stopwatchFactory});
  final bool reminder;
  final DateTime Function()? now;
  // The screen owns this monotonic clock; injection keeps timing tests synthetic.
  final Stopwatch Function()? stopwatchFactory;

  @override
  State<WellbeingSessionScreen> createState() => _WellbeingSessionScreenState();
}

bool wellbeingQuietHours(int hour, int start, int end) =>
    start == end ||
    (start < end ? hour >= start && hour < end : hour >= start || hour < end);

class _WellbeingSessionScreenState extends State<WellbeingSessionScreen>
    with WidgetsBindingObserver {
  final _step = TextEditingController();
  int _draftGeneration = 0;
  int _suggestionRevision = 0;
  int _timerGeneration = 0;
  String _lastStepText = '';
  String? _suggestedStep;
  Timer? _completion;
  Timer? _ticker;
  late final Stopwatch _elapsed;
  Duration _duration = Duration.zero;
  bool _paused = false;
  int _minutes = 5;
  int _quietStart = 22;
  int _quietEnd = 8;
  bool _quiet = true;
  bool _foreground = true;
  bool _visible = true;
  String _routine = 'Pause for a meal or a drink';
  String? _notice;
  DateTime get _now => (widget.now ?? DateTime.now)();
  bool get _running => _completion != null;
  bool get _hasTimer => _running || _paused;
  bool get _canRun =>
      _foreground && _visible && !SafeBoot.instance.restartRequired.value;
  Duration get _remaining => Duration(
      microseconds: (_duration.inMicroseconds - _elapsed.elapsedMicroseconds)
          .clamp(0, _duration.inMicroseconds)
          .toInt());
  bool get _quietNow =>
      widget.reminder &&
      _quiet &&
      wellbeingQuietHours(_now.hour, _quietStart, _quietEnd);

  @override
  void initState() {
    super.initState();
    _elapsed = (widget.stopwatchFactory ?? Stopwatch.new)();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _step.addListener(_stepChanged);
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_safetyChanged);
    SafeBoot.instance.restartRequired.addListener(_safetyChanged);
  }

  void _stopTimers() {
    _timerGeneration++;
    _completion?.cancel();
    _ticker?.cancel();
    _completion = null;
    _ticker = null;
  }

  void _cancel() {
    _stopTimers();
    _elapsed.stop();
    _elapsed.reset();
    _duration = Duration.zero;
    _paused = false;
  }

  void _leave() {
    _cancel();
    _draftGeneration++;
    _suggestionRevision++;
    _suggestedStep = null;
    _notice = null;
    _step.clear();
    _notice =
        'Stopped. Temporary writing was cleared; nothing will restart automatically.';
  }

  void _safetyChanged() {
    if (mounted) setState(_leave);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = ModalRoute.isCurrentOf(context) ?? true;
    if (!_visible) _leave();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground) _leave();
    });
  }

  void _start(int generation) {
    if (!mounted || generation != _timerGeneration || !_canRun || _hasTimer) {
      return;
    }
    _cancel();
    if (_quietNow) {
      setState(
          () => _notice = 'Quiet hours: no reminder started. You can rest.');
      return;
    }
    final duration = Duration(minutes: widget.reminder ? _minutes : 5);
    setState(() {
      _notice = null;
      _duration = duration;
      _elapsed.start();
      _schedule(duration);
    });
  }

  void _schedule(Duration duration) {
    final generation = ++_timerGeneration;
    bool current() =>
        mounted && generation == _timerGeneration && _canRun && _running;
    _completion = Timer(duration, () {
      if (current()) _finish();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!current()) return;
      if (_quietNow) {
        setState(() {
          _cancel();
          _notice = 'Quiet hours: reminder stopped.';
        });
      } else {
        setState(() {});
      }
    });
  }

  void _finish() {
    if (!mounted || !_canRun || !_hasTimer) return;
    final quiet = _quietNow;
    setState(() {
      _cancel();
      _notice = quiet
          ? 'Quiet hours: reminder stopped.'
          : widget.reminder
              ? 'A gentle invitation: $_routine. It is okay to skip.'
              : 'Five minutes are up. You can stop here, rest, or choose another small step.';
    });
  }

  void _pauseTimer(int generation) {
    if (!mounted ||
        generation != _timerGeneration ||
        widget.reminder ||
        !_canRun ||
        !_running) {
      return;
    }
    if (_remaining == Duration.zero) {
      _finish();
      return;
    }
    setState(() {
      _elapsed.stop();
      _stopTimers();
      _paused = true;
    });
  }

  void _resumeTimer(int generation) {
    if (!mounted ||
        generation != _timerGeneration ||
        widget.reminder ||
        !_canRun ||
        !_paused) {
      return;
    }
    final remaining = _remaining;
    if (remaining == Duration.zero) {
      _finish();
      return;
    }
    setState(() {
      _paused = false;
      _notice = null;
      _elapsed.start();
      _schedule(remaining);
    });
  }

  void _stepChanged() {
    if (_step.text == _lastStepText) return;
    _lastStepText = _step.text;
    _suggestionRevision++;
    if (_suggestedStep != null || _notice != null) {
      setState(() {
        _suggestedStep = null;
        _notice = null;
      });
    }
  }

  void _useSuggestion(String text) {
    _suggestionRevision++;
    _suggestedStep = null;
    _notice = null;
    _step.text = text;
    setState(() {});
  }

  void _suggest(String text, int generation) {
    if (!mounted || generation != _timerGeneration || !_canRun) return;
    _suggestionRevision++;
    if (_step.text.trim().isEmpty || _step.text == text) {
      _useSuggestion(text);
    } else {
      setState(() => _suggestedStep = text);
    }
  }

  Widget _replacementChoice(String suggestion) {
    final revision = _suggestionRevision;
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Use this step instead?',
            style: Theme.of(context).textTheme.titleMedium),
        Text(suggestion),
        const Text(
            'Your writing stays unchanged unless you choose Use suggestion.'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
              onPressed: () => setState(() {
                    _suggestionRevision++;
                    _suggestedStep = null;
                  }),
              child: const Text('Keep my step')),
          FilledButton(
              onPressed: () {
                if (_canRun &&
                    revision == _suggestionRevision &&
                    _suggestedStep == suggestion) {
                  _useSuggestion(suggestion);
                }
              },
              child: const Text('Use suggestion')),
        ]),
      ]),
    ));
  }

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_safetyChanged);
    SafeBoot.instance.restartRequired.removeListener(_safetyChanged);
    _step.removeListener(_stepChanged);
    _step.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final generation = _timerGeneration;
    // Elapsed time stays monotonic when the device clock or time zone changes.
    // Wall time remains appropriate for the user's quiet-hours preference.
    final seconds =
        (_remaining.inMicroseconds / Duration.microsecondsPerSecond).ceil();
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.reminder
              ? 'Gentle routine reminder'
              : 'Help me take one step')),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(
              widget.reminder
                  ? 'An invitation, without pressure'
                  : 'Make room for a smaller step',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(widget.reminder
              ? 'Choose one reminder. It is silent, stays in this screen, and is not saved. '
                  'Leaving the screen or app stops it. No background notifications.'
              : 'Choose one thing you can influence. Make it small enough to try: '
                  'open a document, put one thing away, rest, or do something you enjoy. '
                  'You do not have to finish the bigger task.'),
          const SizedBox(height: 16),
          if (widget.reminder) ...[
            DropdownButtonFormField<String>(
              initialValue: _routine,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Routine'),
              items: [
                for (final choice in const [
                  'Pause for a meal or a drink',
                  'Move gently if comfortable',
                  'Make time for something enjoyable',
                  'Begin winding down for sleep'
                ])
                  DropdownMenuItem(value: choice, child: Text(choice))
              ],
              onChanged: _running
                  ? null
                  : (value) => setState(() => _routine = value!),
            ),
            DropdownButtonFormField<int>(
              initialValue: _minutes,
              decoration: const InputDecoration(labelText: 'Remind me in'),
              items: [
                for (final value in [5, 15, 30, 60])
                  DropdownMenuItem(value: value, child: Text('$value minutes'))
              ],
              onChanged: _running
                  ? null
                  : (value) => setState(() => _minutes = value!),
            ),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Respect quiet hours'),
                subtitle: const Text('Uses this device’s local time.'),
                value: _quiet,
                onChanged: _running
                    ? null
                    : (value) => setState(() => _quiet = value)),
            if (_quiet)
              Wrap(spacing: 20, runSpacing: 8, children: [
                _hour('Quiet hours start', _quietStart,
                    (value) => _quietStart = value),
                _hour(
                    'Quiet hours end', _quietEnd, (value) => _quietEnd = value),
              ]),
          ] else ...[
            TextField(
                key: ValueKey(_draftGeneration),
                controller: _step,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                    labelText: 'My smallest next step (optional)',
                    helperText: 'Temporary writing; never saved or sent.',
                    border: OutlineInputBorder())),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final text in [
                'Take a rest',
                'Open the document',
                'Ask for help',
                'Do something enjoyable'
              ])
                ActionChip(
                    label: Text(text),
                    onPressed: () => _suggest(text, generation)),
            ]),
            if (_suggestedStep case final suggestion?)
              _replacementChoice(suggestion),
          ],
          const SizedBox(height: 20),
          if (_hasTimer)
            Text(
                '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} remaining',
                style: Theme.of(context).textTheme.headlineMedium),
          if (_paused)
            const Text(
                'Paused. Your step stays here until you leave this screen or app.'),
          if (_notice != null)
            Semantics(liveRegion: true, child: Text(_notice!)),
          const SizedBox(height: 12),
          if (!widget.reminder && _hasTimer)
            FilledButton.icon(
                onPressed: !_canRun
                    ? null
                    : _paused
                        ? () => _resumeTimer(generation)
                        : () => _pauseTimer(generation),
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                label: Text(_paused ? 'Resume timer' : 'Pause timer'))
          else
            FilledButton(
                onPressed:
                    _hasTimer || !_canRun ? null : () => _start(generation),
                child: Text(widget.reminder
                    ? 'Start this reminder'
                    : 'Try a five-minute timer (optional)')),
          if (SafeBoot.instance.restartRequired.value)
            Text(widget.reminder
                ? 'Restart Neura before starting a reminder.'
                : 'Restart Neura before starting a timer.'),
          OutlinedButton(
              onPressed: () => setState(_leave),
              child: const Text('Stop and clear')),
          const Text(
              'Stopping or skipping is okay. There are no streaks or penalties.'),
        ]),
      ))),
    );
  }

  Widget _hour(String label, int value, ValueChanged<int> change) => SizedBox(
      width: 185,
      child: DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (var hour = 0; hour < 24; hour++)
            DropdownMenuItem(
                value: hour,
                child: Text('${hour.toString().padLeft(2, '0')}:00'))
        ],
        onChanged: _running ? null : (value) => setState(() => change(value!)),
      ));
}
