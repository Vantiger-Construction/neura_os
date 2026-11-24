import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../encrypted_memory/companion_memory_service.dart';
import '../neura_shell/neura_shell.dart';
import '../neura_shell/widgets/neura_penthouse_scene.dart';
import '../profiles/local_profile_service.dart';
import '../reliability/safe_boot.dart';
import '../services/ambient_listening_prefs.dart';
import '../services/ambient_listening_service.dart';
import '../services/neura_local_speech_input.dart';
import '../services/neura_speech_input.dart';
import '../services/wake_word_listener_service.dart';
import '../services/wake_word_prefs.dart';
import '../startup/neura_error_pipeline.dart';
import '../teaching/teach_neura_screen.dart';
import 'day_companion_cues.dart';
import 'home_action.dart';
import 'home_controls.dart';

class DayCompanionScreen extends StatefulWidget {
  const DayCompanionScreen({super.key, this.speechInput, this.memoryService});
  final NeuraSpeechInput? speechInput;
  final CompanionMemoryService? memoryService;

  @override
  State<DayCompanionScreen> createState() => _DayCompanionScreenState();
}

enum _Mic { idle, starting, listening, waiting, stopping }

class _Draft {
  _Draft(this.text) : heard = TimeOfDay.now();
  String text;
  final TimeOfDay heard;
}

class _DayCompanionScreenState extends State<DayCompanionScreen>
    with WidgetsBindingObserver {
  late final _input = widget.speechInput ?? NeuraLocalSpeechInput.instance;
  final _drafts = <_Draft>[];
  final _actions = <HomeAction>[];
  final _gates = Listenable.merge([
    SafeBoot.instance.safeMode,
    SafeBoot.instance.restartRequired,
    NeuraErrorPipeline.instance.fatalError,
    LocalProfileService.instance,
    AmbientListeningPrefsController.instance.enabled,
    WakeWordPrefsController.instance.enabled,
  ]);
  Route<dynamic>? _route;
  bool _foreground = true;
  bool _disposed = false;
  bool _arrange = true;
  bool _ownsInput = false;
  bool _shutdownFailed = false;
  Timer? _resumeAfterSilence;
  bool _saving = false;
  int _epoch = 0, _voiceEpoch = 0;
  _Mic _mic = _Mic.idle;
  StreamSubscription<String>? _finals, _statuses;
  Future<void>? _starting;
  CompanionMemoryPermission? _savePermit;
  ({bool lampOn, bool curtainsClosed})? _before, _after;
  HomeAction? _proposal;
  Timer? _expiry;
  final _proposalAge = Stopwatch();
  HttpClient? _sending;
  String? _notice;

  bool get _allowed =>
      mounted &&
      !_disposed &&
      _foreground &&
      _route?.isCurrent == true &&
      !SafeBoot.instance.safeMode.value &&
      !SafeBoot.instance.restartRequired.value &&
      !LocalProfileService.instance.enabled &&
      NeuraErrorPipeline.instance.fatalError.value == null;
  bool get _otherCapture =>
      AmbientListeningPrefsController.instance.enabled.value ||
      WakeWordPrefsController.instance.enabled.value;
  bool _voiceCurrent(int epoch) =>
      _allowed &&
      !_otherCapture &&
      epoch == _voiceEpoch &&
      (_mic == _Mic.starting || _mic == _Mic.waiting || _mic == _Mic.listening);

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _gates.addListener(_onGate);
    teachNeuraRouteObserver.addListener(_onTop);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  void _onTop(Route<dynamic> top) {
    if (_route != null && !identical(top, _route)) _clear();
  }

  void _onGate() {
    if (!_allowed || _otherCapture) {
      _clear();
    } else {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _clear();
    } else if (mounted) {
      setState(() {});
    }
  }

  void _clear() {
    ++_epoch;
    _savePermit?.revoke();
    _savePermit = null;
    _expiry?.cancel();
    _proposal = null;
    _sending?.close(force: true);
    _sending = null;
    _actions.clear();
    _drafts.clear();
    _before = _after = null;
    _notice = null;
    unawaited(_pause());
    if (!_disposed && mounted) setState(() {});
  }

  Future<void> _pause([String? notice]) async {
    if (notice != null) _notice = notice;
    if (_mic == _Mic.idle || _mic == _Mic.stopping) return;
    ++_voiceEpoch;
    _resumeAfterSilence?.cancel();
    _expiry?.cancel();
    _proposal = null;
    _mic = _Mic.stopping;
    final opening = _starting;
    final finals = _finals, statuses = _statuses;
    _finals = _statuses = null;
    final stopInput = _ownsInput;
    _ownsInput = false;
    if (!_disposed) setState(() {});
    try {
      await Future.wait([
        if (finals != null) finals.cancel(),
        if (statuses != null) statuses.cancel(),
        if (stopInput) _input.stopRecording().then<void>((_) {}),
        if (opening != null) opening,
      ]);
      final input = _input;
      if (input is NeuraLocalSpeechInput && input.shutdownUnconfirmed) {
        _shutdownFailed = true;
      }
    } catch (_) {
      _shutdownFailed = true;
    }
    if (_shutdownFailed) {
      _notice =
          'Microphone shutdown could not be confirmed. Close Neura before retrying.';
    }
    _mic = _Mic.idle;
    if (!_disposed && mounted) setState(() {});
  }

  void _start() {
    if (!_allowed ||
        _otherCapture ||
        _shutdownFailed ||
        _mic != _Mic.idle ||
        _drafts.length >= 12) {
      return;
    }
    final epoch = ++_voiceEpoch;
    _finals = _input.finalPhraseStream.listen((phrase) {
      if (_voiceCurrent(epoch) && _mic == _Mic.listening) _heard(phrase, epoch);
    });
    _statuses = _input.statusStream.listen((status) {
      if (!_voiceCurrent(epoch)) return;
      if (status == NeuraLocalSpeechInput.silenceEnded &&
          defaultTargetPlatform == TargetPlatform.android &&
          _mic == _Mic.listening) {
        setState(() => _mic = _Mic.waiting);
        _resumeAfterSilence = Timer(const Duration(seconds: 1), () {
          if (!_voiceCurrent(epoch)) return;
          setState(() => _mic = _Mic.starting);
          _starting = _openMic(epoch, first: false);
        });
      } else {
        unawaited(_pause(status));
      }
    });
    setState(() {
      _mic = _Mic.starting;
      _notice = null;
    });
    _starting = _openMic(epoch, first: true);
  }

  Future<void> _openMic(int epoch, {required bool first}) async {
    try {
      if (first) {
        await Future.wait([
          AmbientListeningService.instance.stop(),
          WakeWordListenerService.instance.stop(),
        ]).timeout(const Duration(seconds: 3));
      } else {
        // Android completes each recognition request after one final result.
        await _input.stopRecording();
      }
      if (!_voiceCurrent(epoch)) return;
      _ownsInput = true;
      final ok = await _input.startRecording();
      if (!_voiceCurrent(epoch)) return;
      if (ok) {
        setState(() => _mic = _Mic.listening);
      } else {
        unawaited(_pause(
            'Local speech recognition is unavailable. Check the microphone and installed recognition language.'));
      }
    } catch (_) {
      if (_voiceCurrent(epoch)) {
        unawaited(_pause('Local listening could not start.'));
      }
    }
  }

  void _heard(String phrase, int epoch) {
    if (DayCompanionCues.wantsStop(phrase)) {
      unawaited(_pause('Listening paused. Review your drafts below.'));
      return;
    }
    final action =
        _actions.where((action) => action.matches(phrase)).firstOrNull;
    final cue = DayCompanionCues.roomCue(phrase);
    if (action != null) {
      _propose(action);
    } else if (cue != null) {
      final linked = _actions.where((action) => action.cue == cue).firstOrNull;
      if (linked != null) _propose(linked);
      if (_arrange) {
        final shell = NeuraShell.of(context);
        final before = shell.penthouse;
        shell.arrangePenthouse(cue);
        if (shell.penthouse != before) {
          setState(() {
            _before = before;
            _after = shell.penthouse;
          });
        }
      }
    } else {
      final note = DayCompanionCues.note(phrase);
      if (note != null &&
          _drafts.length < 12 &&
          !_drafts.any((d) => d.text.toLowerCase() == note.toLowerCase())) {
        setState(() => _drafts.insert(0, _Draft(note)));
        if (_drafts.length == 12) {
          unawaited(_pause(
              'Drafts are full. Save or dismiss one to continue listening.'));
          return;
        }
      }
    }
    if (defaultTargetPlatform == TargetPlatform.android &&
        _voiceCurrent(epoch)) {
      setState(() => _mic = _Mic.starting);
      _starting = _openMic(epoch, first: false);
    }
  }

  void _propose(HomeAction action) {
    if (!_allowed || _sending != null || !_actions.contains(action)) return;
    _expiry?.cancel();
    _proposalAge
      ..reset()
      ..start();
    setState(() => _proposal = action);
    _expiry = Timer(const Duration(minutes: 1), () {
      if (mounted) setState(() => _proposal = null);
    });
  }

  Future<void> _send(HomeAction action) async {
    if (!_allowed ||
        !identical(action, _proposal) ||
        _proposalAge.elapsed >= const Duration(minutes: 1) ||
        !_actions.contains(action) ||
        _sending != null) {
      return;
    }
    final epoch = _epoch;
    final client = HttpClient();
    _expiry?.cancel();
    setState(() {
      _sending = client;
      _proposal = null;
      _notice = null;
    });
    bool current() =>
        _allowed && _epoch == epoch && identical(client, _sending);
    var accepted = false;
    try {
      accepted = await action
          .send(client, current: current)
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // The hub may have received a timed-out request. Never retry it here.
    } finally {
      client.close(force: true);
      if (current()) {
        setState(() {
          _sending = null;
          _notice = accepted
              ? 'Home Assistant received the request. Check the device for the result.'
              : 'Delivery was not confirmed. Check Home Assistant before trying again.';
        });
      }
    }
  }

  Future<void> _save(_Draft draft) async {
    final text = draft.text.trim();
    if (!_allowed || _saving || !_drafts.contains(draft) || text.isEmpty) {
      return;
    }
    final epoch = _epoch;
    setState(() => _saving = true);
    try {
      final memory =
          widget.memoryService ?? await CompanionMemoryService.local();
      if (!_allowed || _epoch != epoch) return;
      final permit = memory.authorize(CompanionMemoryUse.remember,
          directUserGesture: true);
      _savePermit = permit;
      await memory.remember(permit, text);
      if (_allowed && _epoch == epoch) {
        setState(() {
          _drafts.remove(draft);
          _notice = 'Saved to encrypted companion notes.';
        });
      }
    } catch (_) {
      if (_allowed && _epoch == epoch) {
        setState(() => _notice =
            'Save was not confirmed. Check your companion notes before retrying.');
      }
    } finally {
      _savePermit?.revoke();
      _savePermit = null;
      if (!_disposed && mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _gates.removeListener(_onGate);
    teachNeuraRouteObserver.removeListener(_onTop);
    WidgetsBinding.instance.removeObserver(this);
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = NeuraShell.of(context);
    final room = shell.penthouse;
    final action = _proposal;
    final allowed = _allowed;
    return Scaffold(
        appBar: AppBar(title: const Text('Day Companion')),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
              'Neura listens on this screen and drafts plans, commitments, preferences and “remember” requests on this device. Use it where everyone agrees to be heard.'),
          const Text(
              'Only notes you tap Save on are kept. Leaving this screen or switching apps clears drafts and stops listening.'),
          if (_otherCapture)
            const Text(
                'Turn off ambient clips and Hey Neura in Privacy to use this listening session.'),
          FilledButton.icon(
              onPressed: switch (_mic) {
                _Mic.idle
                    when allowed &&
                        !_shutdownFailed &&
                        !_otherCapture &&
                        _drafts.length < 12 =>
                  _start,
                _Mic.starting || _Mic.listening || _Mic.waiting => () =>
                    unawaited(_pause()),
                _ => null,
              },
              icon: Icon(_mic == _Mic.listening ? Icons.mic : Icons.hearing),
              label: Text(switch (_mic) {
                _Mic.idle => 'Start listening locally',
                _Mic.starting => 'Starting microphone · cancel',
                _Mic.listening => 'Listening locally · pause',
                _Mic.waiting => 'Between listening windows · pause',
                _Mic.stopping => 'Stopping microphone…',
              })),
          if (_notice != null)
            Semantics(liveRegion: true, child: Text(_notice!)),
          if (action != null && allowed)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      Text(
                          'Run “${action.label}” on ${action.endpoint.authority}?'),
                      const Text(
                          'Home Assistant runs the automation assigned to this link. Alexa and other cloud-connected devices may send the command to their provider.'),
                      Wrap(children: [
                        TextButton(
                            onPressed: () => setState(() => _proposal = null),
                            child: const Text('Cancel')),
                        FilledButton(
                            onPressed: () => _send(action),
                            child: const Text('Run once'))
                      ])
                    ]))),
          if (_sending != null) const Text('Sending to Home Assistant…'),
          const SizedBox(height: 12),
          SizedBox(
              height: 150,
              child: Semantics(
                  label:
                      'Penthouse. Lamp ${room.lampOn ? "on" : "off"}, curtains ${room.curtainsClosed ? "closed" : "open"}.',
                  child: const NeuraPenthouseScene())),
          SwitchListTile(
              value: _arrange,
              onChanged: allowed ? (v) => setState(() => _arrange = v) : null,
              title: const Text('Let Neura arrange her penthouse'),
              subtitle: const Text(
                  'Try “I’m winding down”, “I need to focus”, or “open the curtains”.')),
          if (_before != null && _after == room && allowed)
            TextButton(
                onPressed: () {
                  shell.setPenthouse(_before!);
                  setState(() => _before = _after = null);
                },
                child: const Text('Undo room change')),
          if (allowed)
            DayHomeControls(
                key: ValueKey(_epoch),
                actions: _actions,
                onAdd: (a) => setState(() => _actions.add(a)),
                onSelect: _propose,
                onRemove: (a) => setState(() {
                      _actions.remove(a);
                      if (identical(a, _proposal)) _proposal = null;
                    })),
          const Divider(),
          Text('Draft notes (${_drafts.length})',
              style: Theme.of(context).textTheme.titleMedium),
          for (final draft in _drafts)
            Card(
                key: ObjectKey(draft),
                child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(children: [
                      TextFormField(
                          initialValue: draft.text,
                          enableIMEPersonalizedLearning: false,
                          enabled: !_saving,
                          maxLength: 320,
                          onChanged: (v) => draft.text = v,
                          decoration: InputDecoration(
                              labelText:
                                  'Heard at ${draft.heard.format(context)}')),
                      Wrap(children: [
                        TextButton(
                            onPressed: _saving
                                ? null
                                : () => setState(() => _drafts.remove(draft)),
                            child: const Text('Dismiss')),
                        FilledButton(
                            onPressed: _saving ? null : () => _save(draft),
                            child: const Text('Save note'))
                      ])
                    ]))),
        ])));
  }
}
