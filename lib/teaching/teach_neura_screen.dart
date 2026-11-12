import 'dart:async';

import 'package:flutter/material.dart';

import 'neura_teaching_preferences.dart';
import 'neura_teaching_service.dart';

/// Synchronously revokes drafts even when a covering route is removed before
/// the next frame. Register this observer on the teaching screen's Navigator.
class TeachNeuraRouteObserver extends NavigatorObserver {
  final _listeners = <void Function(Route<dynamic>)>{};

  void addListener(void Function(Route<dynamic>) listener) =>
      _listeners.add(listener);
  void removeListener(void Function(Route<dynamic>) listener) =>
      _listeners.remove(listener);

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    for (final listener in _listeners.toList()) {
      listener(topRoute);
    }
  }
}

final teachNeuraRouteObserver = TeachNeuraRouteObserver();

/// Explicit, reviewable choices only: no chat-derived preference proposals.
class NeuraTeachScreen extends StatefulWidget {
  const NeuraTeachScreen({super.key, this.service});

  final NeuraTeachingService? service;

  @override
  State<NeuraTeachScreen> createState() => _NeuraTeachScreenState();
}

class _NeuraTeachScreenState extends State<NeuraTeachScreen>
    with WidgetsBindingObserver {
  late final NeuraTeachingService _service;
  NeuraTeachingPermit? _permit;
  NeuraAnswerDetail? _answer;
  NeuraPlanSize? _plan;
  String? _remove;
  String? _notice;
  bool _submitting = false;
  Route<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? NeuraTeachingService.instance;
    WidgetsBinding.instance.addObserver(this);
    _service.addListener(_changed);
    teachNeuraRouteObserver.addListener(_routeChanged);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await _service.load();
    } catch (_) {
      if (mounted) {
        setState(() => _notice = 'Preferences could not be confirmed. '
            'Review again before making a change.');
      }
    }
  }

  void _clearDraft() {
    _permit?.revoke();
    _permit = null;
    _answer = null;
    _plan = null;
    _remove = null;
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (!_service.available ||
          (!_submitting && _permit != null && !_permit!.valid)) {
        _clearDraft();
      }
    });
  }

  void _routeChanged(Route<dynamic> topRoute) {
    if (_route != null && !identical(_route, topRoute)) {
      _clearDraft();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    // ModalRoute registers an isCurrent dependency, including dialog coverage.
    if (ModalRoute.of(context)?.isCurrent == false) _clearDraft();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(_clearDraft);
    }
  }

  @override
  void dispose() {
    _clearDraft();
    _service.removeListener(_changed);
    teachNeuraRouteObserver.removeListener(_routeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _enabled =>
      identical(
          teachNeuraRouteObserver.navigator, Navigator.maybeOf(context)) &&
      _route?.isCurrent == true &&
      _service.available &&
      _service.loaded &&
      !_service.busy &&
      !_submitting;

  void _propose(
      {NeuraAnswerDetail? answer, NeuraPlanSize? plan, String? remove}) {
    if (!_enabled || ModalRoute.of(context)?.isCurrent == false) return;
    _clearDraft();
    try {
      final permit = _service.beginChange(directUserGesture: true);
      setState(() {
        _permit = permit;
        _answer = answer;
        _plan = plan;
        _remove = remove;
        _notice = null;
      });
    } catch (_) {
      setState(() => _notice = 'This change is no longer available. '
          'Review preferences and choose again.');
    }
  }

  Future<void> _apply({required bool today}) async {
    final permit = _permit;
    if (permit != null && !permit.valid) {
      setState(() {
        _clearDraft();
        _notice = 'This choice expired. Review preferences and choose again.';
      });
      return;
    }
    if (permit == null ||
        !_enabled ||
        ModalRoute.of(context)?.isCurrent == false) return;
    final answer = _answer;
    final plan = _plan;
    final remove = _remove;
    setState(() => _submitting = true);
    try {
      if (remove == 'answer') {
        await _service.removeAnswerDetail(permit);
      } else if (remove == 'plan') {
        await _service.removePlanSize(permit);
      } else if (answer != null) {
        await _service.setAnswerDetail(permit, answer, today: today);
      } else if (plan != null) {
        await _service.setPlanSize(permit, plan, today: today);
      }
      if (mounted && identical(_permit, permit)) {
        setState(() {
          _clearDraft();
          _notice = remove != null
              ? 'Preference removed.'
              : today
                  ? 'Temporary preference applied.'
                  : 'Preference saved.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _clearDraft();
          _notice = 'The outcome of this change is unconfirmed. '
              'Review preferences, then choose again to retry.';
        });
      }
    } finally {
      permit.revoke();
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _review(String title, String? saved, String? current, bool temporary) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        Text(
            'Saved: ${!_service.loaded ? 'Not confirmed' : saved ?? 'Default (no preference)'}'),
        Text(
            'Current: ${!_service.loaded ? 'Not confirmed' : current ?? 'Default (no preference)'}'
            '${temporary ? ' (just today)' : ''}'),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saved = _service.saved;
    final current = _service.current;
    return Scaffold(
      appBar: AppBar(title: const Text('Teach Neura')),
      body: SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('You choose what Neura remembers. Preferences are never '
              'inferred automatically from your chats.'),
          const SizedBox(height: 12),
          const Text(
              'These choices affect future replies and starter suggestions '
              'only. They do not rewrite existing drafts or change permissions.'),
          const SizedBox(height: 12),
          const Text(
              'Saved preferences stay locally encrypted on this installation. '
              'Just today choices stay only in memory and expire at local midnight, '
              'when the app goes into the background, in Safe Mode, in profile '
              'mode, or when the app restarts.'),
          if (!_service.available)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child:
                    Text('Teach Neura is unavailable in Safe Mode, recovery, '
                        'or profile mode. No changes can be made here.')),
          if (_service.busy || _submitting) const LinearProgressIndicator(),
          if (_notice != null) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(_notice!)),
          ],
          if (_service.error != null)
            const Text('Preference storage needs attention. Review preferences '
                'before trying another change.'),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  onPressed: _service.busy || _submitting
                      ? null
                      : () {
                          setState(_clearDraft);
                          unawaited(_load());
                        },
                  child: const Text('Review preferences'))),
          _review('Answer detail', saved.answerDetail?.label,
              current.answerDetail?.label, _service.answerIsTemporary),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final value in NeuraAnswerDetail.values)
              OutlinedButton(
                  key: ValueKey('answer-${value.name}'),
                  onPressed: _enabled ? () => _propose(answer: value) : null,
                  child: Text(value.label)),
            TextButton(
                key: const ValueKey('remove-answer'),
                onPressed: _enabled &&
                        (saved.answerDetail != null ||
                            current.answerDetail != null)
                    ? () => _propose(remove: 'answer')
                    : null,
                child: const Text('Remove answer preference')),
          ]),
          _review('Starter plan size', saved.planSize?.label,
              current.planSize?.label, _service.planIsTemporary),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final value in NeuraPlanSize.values)
              OutlinedButton(
                  key: ValueKey('plan-${value.name}'),
                  onPressed: _enabled ? () => _propose(plan: value) : null,
                  child: Text(value.label)),
            TextButton(
                key: const ValueKey('remove-plan'),
                onPressed: _enabled &&
                        (saved.planSize != null || current.planSize != null)
                    ? () => _propose(remove: 'plan')
                    : null,
                child: const Text('Remove plan preference')),
          ]),
          if (_permit != null)
            Card(
                child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _remove != null
                            ? 'Remove saved and temporary ${_remove == 'answer' ? 'answer detail' : 'starter plan size'} preferences?'
                            : _answer != null
                                ? 'Proposed answer detail: ${_answer!.label}'
                                : 'Proposed starter plan size: ${_plan!.label}',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (_remove == null) ...[
                        FilledButton(
                            onPressed: _enabled
                                ? () => unawaited(_apply(today: true))
                                : null,
                            child: const Text('Just today')),
                        FilledButton(
                            onPressed: _enabled
                                ? () => unawaited(_apply(today: false))
                                : null,
                            child: const Text('Save preference')),
                      ] else
                        FilledButton(
                            onPressed: _enabled
                                ? () => unawaited(_apply(today: false))
                                : null,
                            child: const Text('Remove preference')),
                      TextButton(
                          onPressed:
                              _submitting ? null : () => setState(_clearDraft),
                          child: const Text('No')),
                    ]),
                  ]),
            )),
        ]),
      )),
    );
  }
}
