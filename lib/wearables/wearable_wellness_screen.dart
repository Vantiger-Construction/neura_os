import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constitution/neura_constitution_service.dart';
import '../intent_compiler/neura_action_graph.dart';
import '../modules/support/private_support_state.dart';
import '../modules/support/support_page_shortcuts.dart';
import '../reliability/safe_boot.dart';
import 'wearable_gateway.dart';
import 'wearable_route_observer.dart';
import 'wearable_snapshot.dart';

class WearableWellnessScreen extends StatefulWidget {
  const WearableWellnessScreen(
      {super.key, this.gateway, this.copyText, this.now});
  final WearableGateway? gateway;
  final Future<void> Function(String)? copyText;
  final DateTime Function()? now;
  @override
  State<WearableWellnessScreen> createState() => _WearableWellnessScreenState();
}

class _WearableWellnessScreenState
    extends PrivateSupportState<WearableWellnessScreen> {
  late final WearableGateway _gateway;
  final _bodyNote = TextEditingController();
  final _selected = <WearableMetric>{};
  final _share = <WearableMetric>{};
  Set<WearableMetric> _granted = {};
  bool? _available;
  WearableSnapshot? _snapshot;
  String? _preview;
  String? _notice;
  String? _readId;
  bool _busy = false;
  bool _includeNote = false;
  bool _approved = false;
  bool _resetting = false;
  String _noteValue = '';
  DateTime? _approvedAt;
  Timer? _approvalTimer;
  ModalRoute<dynamic>? _route;

  bool get _tracked =>
      identical(wearableRouteObserver.navigator, Navigator.maybeOf(context));
  bool get _mayRead => mayReadSaved && _tracked && _route?.isCurrent == true;
  DateTime get _now => (widget.now ?? DateTime.now)();
  bool _current(int epoch) => isCurrent(epoch) && _mayRead;
  VoidCallback _guard(int epoch, VoidCallback action) => () {
        if (_current(epoch) && !_busy) action();
      };

  @override
  void initState() {
    _gateway = widget.gateway ?? const HealthConnectGateway();
    super.initState();
    _bodyNote.addListener(_noteEdited);
    wearableRouteObserver.addListener(_topChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  void _topChanged(Route<dynamic> top) {
    if (mounted && _route != null && top != _route) setState(invalidateDraft);
  }

  void _cancelNative() {
    final id = _readId;
    _readId = null;
    if (id != null) unawaited(_gateway.cancel(id).catchError((_) {}));
  }

  void _revokePreview() {
    _approvalTimer?.cancel();
    _approvalTimer = null;
    _approved = false;
    _approvedAt = null;
    _preview = null;
  }

  void _noteEdited() {
    if (_resetting || _noteValue == _bodyNote.text) return;
    _noteValue = _bodyNote.text;
    setState(() {
      requestGeneration++;
      _revokePreview();
    });
  }

  @override
  void clearPrivateContent() {
    _cancelNative();
    _revokePreview();
    _snapshot = null;
    _selected.clear();
    _share.clear();
    _granted = {};
    _includeNote = false;
    _resetting = true;
    _bodyNote.clear();
    _noteValue = '';
    _resetting = false;
    _notice =
        'Temporary readings and body note cleared. Nothing resumes automatically.';
  }

  Future<void> _check() async {
    if (!_mayRead || _busy) return;
    final epoch = ++requestGeneration;
    setState(() {
      _busy = true;
      _snapshot = null;
      _share.clear();
      _revokePreview();
      _notice = null;
    });
    try {
      final available =
          await _gateway.available().timeout(const Duration(seconds: 8));
      if (!_current(epoch)) return;
      setState(() => _available = available);
      if (available) {
        final granted =
            await _gateway.permissions().timeout(const Duration(seconds: 8));
        if (!_current(epoch)) return;
        setState(() {
          _granted = granted;
          _notice =
              'Connector available. Select data types, grant permission if needed, then Read.';
        });
      } else {
        setState(() {
          _granted = {};
          _notice =
              'This connector requires Android 14+ with Health Connect. No readings were obtained.';
        });
      }
    } catch (_) {
      if (_current(epoch)) {
        setState(() => _notice =
            'Connection could not be checked. No readings were obtained.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _permissions() async {
    if (!_mayRead || _busy || _available != true || _selected.isEmpty) return;
    final epoch = ++requestGeneration;
    final selected = Set<WearableMetric>.of(_selected);
    setState(() {
      _busy = true;
      _snapshot = null;
      _share.clear();
      _revokePreview();
    });
    try {
      await _gateway
          .requestPermissions(selected)
          .timeout(const Duration(minutes: 2));
      if (_current(epoch)) {
        setState(() => _notice =
            'Permission step finished. Press Read yourself; nothing was read automatically.');
      }
    } catch (_) {
      if (_current(epoch)) {
        setState(() => _notice =
            'Permission outcome is unconfirmed. Check Android Health Connect controls.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _read() async {
    if (!_mayRead || _busy || _available != true || _selected.isEmpty) return;
    final epoch = ++requestGeneration;
    final id = HealthConnectGateway.requestId();
    _readId = id;
    final selected = Set<WearableMetric>.of(_selected);
    setState(() {
      _busy = true;
      _snapshot = null;
      _share.clear();
      _revokePreview();
      _notice = null;
    });
    try {
      final snapshot = await _gateway
          .read(id, selected)
          .timeout(const Duration(seconds: 12));
      if (!_current(epoch) || _readId != id) return;
      setState(() {
        _snapshot = snapshot;
        _notice =
            'Selected records read into this screen only. Nothing was sent to Neura chat or a clinic.';
      });
    } catch (_) {
      if (_current(epoch)) {
        setState(() => _notice =
            'Read did not complete or returned unsupported data. No values are shown as normal or zero.');
      }
    } finally {
      if (_readId == id) _cancelNative();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manage() async {
    if (!mayUse || !_tracked || _busy) return;
    setState(invalidateDraft);
    final epoch = requestGeneration;
    setState(() => _busy = true);
    try {
      final opened = await _gateway
          .managePermissions()
          .timeout(const Duration(seconds: 8));
      if (isCurrent(epoch)) {
        setState(() => _notice = opened
            ? 'Use Android’s controls to change or revoke access. No permission change is confirmed by opening settings.'
            : 'Settings could not be opened. Use Android Settings → Health Connect → App permissions.');
      }
    } catch (_) {
      if (isCurrent(epoch)) {
        setState(() => _notice =
            'Open Android Settings → Health Connect → App permissions to revoke access.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _review() {
    if (!_mayRead || _busy || _snapshot == null || _share.isEmpty) return;
    try {
      final text = _snapshot!.selectedText(_share);
      setState(() {
        requestGeneration++;
        _revokePreview();
        _preview =
            '$text${_includeNote && _bodyNote.text.trim().isNotEmpty ? '\n\nMy own body note (not a sensor finding):\n${_bodyNote.text.trim()}' : ''}';
      });
    } on FormatException catch (error) {
      setState(() => _notice = error.message);
    }
  }

  bool get _freshApproval {
    final at = _approvedAt;
    return _approved &&
        at != null &&
        !_now.isBefore(at) &&
        _now.difference(at) < const Duration(minutes: 2);
  }

  void _approve(int epoch, bool value) {
    if (!_current(epoch) || _busy || _preview == null) return;
    setState(() {
      requestGeneration++;
      _approvalTimer?.cancel();
      _approved = value;
      _approvedAt = value ? _now : null;
      if (value) {
        _approvalTimer = Timer(const Duration(minutes: 2), () {
          if (mounted) {
            setState(() {
              requestGeneration++;
              _approved = false;
              _approvedAt = null;
            });
          }
        });
      }
    });
  }

  Future<void> _copy() async {
    if (!_mayRead || _busy || !_freshApproval || _preview == null) return;
    final epoch = requestGeneration;
    var completionEpoch = epoch;
    final text = _preview!;
    final selected = Set<WearableMetric>.of(_share);
    setState(() => _busy = true);
    try {
      await NeuraConstitutionService.instance
          .load()
          .timeout(const Duration(seconds: 8));
      if (!_current(epoch) || !_freshApproval || _preview != text) return;
      final policy = NeuraConstitutionService.instance.current.evaluateEffect(
          effect: NeuraActionEffect.externalMessage,
          at: _now,
          containsSensitiveContent: true);
      if (!policy.allowed) {
        setState(() => _notice =
            '${policy.reason} Review Personal Constitution sharing settings.');
        return;
      }
      final permissions =
          await _gateway.permissions().timeout(const Duration(seconds: 8));
      if (!_current(epoch) || !_freshApproval || _preview != text) return;
      if (!permissions.containsAll(selected)) {
        setState(invalidateDraft);
        setState(() => _notice =
            'Health permissions changed. The readings and approval were cleared.');
        return;
      }
      requestGeneration++;
      final completion = requestGeneration;
      completionEpoch = completion;
      setState(() {
        _approved = false;
        _approvedAt = null;
        _approvalTimer?.cancel();
      });
      await (widget.copyText ??
          (text) => Clipboard.setData(ClipboardData(text: text)))(text);
      if (_current(completion)) {
        setState(() => _notice =
            'Selected text copied. You choose where to paste it; nothing was sent automatically.');
      }
    } catch (_) {
      if (_current(completionEpoch)) {
        setState(() => _notice =
            'Copy or permission confirmation did not complete. No automatic retry was made.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _cancelNative();
    _approvalTimer?.cancel();
    wearableRouteObserver.removeListener(_topChanged);
    _bodyNote.removeListener(_noteEdited);
    _bodyNote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final epoch = requestGeneration;
    final canRead = _mayRead && !_busy;
    return SupportPageShortcuts(
        child: Scaffold(
      appBar: AppBar(title: const Text('Wearable body awareness'), actions: [
        IconButton(
            tooltip: 'Stop and clear readings',
            onPressed: () => setState(invalidateDraft),
            icon: const Icon(Icons.stop_circle_outlined)),
      ]),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text(
              'Read selected heart rate, steps and sleep-session records from this phone’s Android user. '
              'The client must use their own phone/profile; a typed name cannot switch whose records are read.'),
          const SizedBox(height: 12),
          const Text(
              'Synced records, not live measurements. Wearables and source apps may delay, omit or misrecord data. '
              'Neura does not diagnose conditions, infer how you feel, or monitor emergencies.'),
          OutlinedButton(
              onPressed: canRead ? _guard(epoch, _check) : null,
              child: const Text('Check connection and permissions')),
          for (final metric in WearableMetric.values)
            CheckboxListTile(
                key: ValueKey('read-${metric.key}'),
                contentPadding: EdgeInsets.zero,
                title: Text(metric.label),
                subtitle: Text(_granted.contains(metric)
                    ? 'Android permission granted; reading still needs your action.'
                    : 'Permission not checked or not granted.'),
                value: _selected.contains(metric),
                onChanged: !canRead
                    ? null
                    : (value) {
                        if (!_current(epoch)) return;
                        setState(() {
                          requestGeneration++;
                          _snapshot = null;
                          _share.clear();
                          _revokePreview();
                          if (value == true) {
                            _selected.add(metric);
                          } else {
                            _selected.remove(metric);
                          }
                        });
                      }),
          FilledButton(
              onPressed: canRead && _available == true && _selected.isNotEmpty
                  ? _guard(epoch, _permissions)
                  : null,
              child: const Text('Grant selected Android permissions')),
          const Text(
              'The system permission screen may clear your selection when Neura loses focus. '
              'After returning, select types again and press Read. Granting permission never reads automatically.'),
          FilledButton(
              onPressed: canRead && _available == true && _selected.isNotEmpty
                  ? _guard(epoch, _read)
                  : null,
              child: Text(
                  _busy ? 'Working…' : 'Read selected data (last 24 hours)')),
          OutlinedButton(
              onPressed: mayUse && _tracked && !_busy ? _manage : null,
              child: const Text('Manage or revoke Android permissions')),
          if (_notice != null)
            Semantics(liveRegion: true, child: Text(_notice!)),
          if (SafeBoot.instance.safeMode.value ||
              SafeBoot.instance.restartRequired.value)
            const Text(
                'Safe Mode or recovery: health reads and copying are blocked. You can still manage Android permissions.'),
          if (_snapshot != null) ...[
            const Divider(),
            Text(
                'Window: ${_snapshot!.from.toLocal()} to ${_snapshot!.to.toLocal()} (device time).'),
            const Text(
                'No client record is saved here. Source apps may include phone data as well as wearables.'),
            for (final metric in WearableMetric.values
                .where(_snapshot!.readings.containsKey)) ...[
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(metric.label),
                  subtitle: Text(_snapshot!.readings[metric]!.describe())),
              if (_snapshot!.readings[metric]!.hasData)
                CheckboxListTile(
                    key: ValueKey('share-${metric.key}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        'Include ${metric.label.toLowerCase()} in my reviewed text'),
                    value: _share.contains(metric),
                    onChanged: !canRead
                        ? null
                        : (value) {
                            if (!_current(epoch)) return;
                            setState(() {
                              requestGeneration++;
                              _revokePreview();
                              if (value == true) {
                                _share.add(metric);
                              } else {
                                _share.remove(metric);
                              }
                            });
                          }),
            ],
            TextField(
                key: ValueKey('body-note-$editorGeneration'),
                controller: _bodyNote,
                enabled: canRead,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                autocorrect: false,
                decoration: const InputDecoration(
                    labelText: 'How does your body feel? (optional)',
                    border: OutlineInputBorder())),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include my body note'),
                value: _includeNote,
                onChanged: !canRead
                    ? null
                    : (value) {
                        if (!_current(epoch)) return;
                        setState(() {
                          requestGeneration++;
                          _revokePreview();
                          _includeNote = value ?? false;
                        });
                      }),
            FilledButton(
                onPressed: canRead && _share.isNotEmpty
                    ? _guard(epoch, _review)
                    : null,
                child: const Text('Review selected readings for copying')),
          ],
          if (_preview != null) ...[
            const Divider(),
            // Selection would expose the system Copy menu before approval.
            Text(_preview!, key: const ValueKey('wearable-review-text')),
            const Text(
                'Copying places health text on your system clipboard, which other apps or synced devices may access. '
                'You can paste it into Neura chat to discuss it or into a clinic report yourself. '
                'Sending to a cloud model still needs its own approval; no model or clinic receives data from this screen.'),
            CheckboxListTile(
                key: const ValueKey('approve-wearable-copy'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                    'These are my records and I approve copying only this reviewed text'),
                value: _approved,
                onChanged: !canRead
                    ? null
                    : (value) => _approve(epoch, value ?? false)),
            FilledButton(
                onPressed:
                    canRead && _freshApproval ? _guard(epoch, _copy) : null,
                child: const Text('Copy reviewed readings')),
          ],
          TextButton(
              onPressed: () => setState(invalidateDraft),
              child: const Text('Stop and clear')),
          const Text(
              'Leaving this screen or app clears temporary readings and notes, including pending approvals. '
              'Already-copied text cannot be retracted. Clearing this screen does not revoke Android permissions '
              'or delete records held by Health Connect or your wearable app.'),
        ]),
      ))),
    ));
  }
}
