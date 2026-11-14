import 'package:flutter/material.dart';

import '../../reliability/safe_boot.dart';
import 'guided_support_activity.dart';
import 'guided_support_store.dart';
import 'support_page_shortcuts.dart';
import 'support_suggestion_choices.dart';

class SupportSuggestionScreen extends StatefulWidget {
  const SupportSuggestionScreen({super.key, this.store});
  final GuidedSupportStore? store;

  @override
  State<SupportSuggestionScreen> createState() =>
      _SupportSuggestionScreenState();
}

class _SupportSuggestionScreenState extends State<SupportSuggestionScreen>
    with WidgetsBindingObserver {
  GuidedSupportStore get _store => widget.store ?? GuidedSupportStore.instance;
  SupportSuggestionChoices? _choices;
  bool _foreground = true;
  bool _visible = true;
  bool _busy = false;
  bool _approved = false;
  int _epoch = 0;
  String? _notice;

  bool get _active => mounted && _foreground && _visible;
  bool get _private =>
      _active &&
      !SafeBoot.instance.safeMode.value &&
      !SafeBoot.instance.restartRequired.value;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_safetyChanged);
    SafeBoot.instance.restartRequired.addListener(_safetyChanged);
  }

  void _hide() {
    _epoch++;
    _choices = null;
    _approved = false;
    _notice = 'Choices hidden. Open them again when you are ready.';
  }

  void _safetyChanged() {
    if (mounted) setState(_hide);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    if (_visible && !visible) _hide();
    _visible = visible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground) _hide();
    });
  }

  Future<void> _open() async {
    if (!_private || _busy) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _notice = null;
      _choices = null;
      _approved = false;
    });
    try {
      final choices = await _store.readChoices();
      if (_private && epoch == _epoch) setState(() => _choices = choices);
    } catch (_) {
      if (_active && epoch == _epoch) {
        setState(() =>
            _notice = 'Choices could not be opened. Nothing was changed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final choices = _choices;
    if (!_private || _busy || !_approved || choices == null) return;
    final epoch = _epoch;
    setState(() => _busy = true);
    bool approved() => _private && epoch == _epoch && _approved;
    try {
      await _store.saveChoicesAfterConfirmation(choices,
          stillApproved: approved);
      if (approved()) {
        setState(() {
          _approved = false;
          _notice = 'Suggestion choices saved on this device.';
        });
      }
    } catch (_) {
      if (_active && epoch == _epoch) {
        setState(() {
          _approved = false;
          _notice =
              'Saving did not complete. Open your saved choices to check them.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forget() async {
    if (!_active || _busy) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _approved = false;
    });
    try {
      await _store.forgetChoices();
      if (_active && epoch == _epoch) {
        setState(() {
          _choices = null;
          _notice =
              'Suggestion choices forgotten. Your remembered activity is unchanged.';
        });
      }
    } catch (_) {
      if (_active && epoch == _epoch) {
        setState(() => _notice = 'Deletion could not be verified. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _edit(SupportSuggestionChoices choices,
      SupportSuggestionChoices previous, int displayedEpoch) {
    if (!_private ||
        _busy ||
        displayedEpoch != _epoch ||
        !identical(previous, _choices)) {
      return;
    }
    _epoch++;
    setState(() {
      _choices = choices;
      _approved = false;
      _notice = null;
    });
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_safetyChanged);
    SafeBoot.instance.restartRequired.removeListener(_safetyChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayedEpoch = _epoch;
    return SupportPageShortcuts(
        child: Scaffold(
      appBar: AppBar(title: const Text('Suggestion choices')),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text(
              'Control the remembered activity offered in guided support. '
              'These choices do not change chat, reminders, or other suggestions. '
              'Every activity remains available when you choose it yourself.'),
          const SizedBox(height: 16),
          if (!_private)
            const Text(
                'Saved choices are unavailable while hidden, in Safe Mode, or during recovery. Forgetting remains available.'),
          if (_notice != null)
            Semantics(liveRegion: true, child: Text(_notice!)),
          if (_choices == null)
            OutlinedButton(
                onPressed: _private && !_busy ? _open : null,
                child: Text(_busy ? 'Opening…' : 'Open my suggestion choices')),
          if (_choices case final choices?) ...[
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Only suggest when I ask'),
                subtitle: const Text(
                    'Wait for Show suggested activity before offering a remembered activity.'),
                value: choices.onlyWhenAsked,
                onChanged: _busy
                    ? null
                    : (value) => _edit(
                        SupportSuggestionChoices(
                            onlyWhenAsked: value, excluded: choices.excluded),
                        choices,
                        displayedEpoch)),
            const Text('Do not suggest these activities:'),
            for (final activity in GuidedSupportActivity.values)
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(activity.label),
                  value: choices.excluded.contains(activity),
                  onChanged: _busy
                      ? null
                      : (value) {
                          final excluded = {...choices.excluded};
                          if (value == true) {
                            excluded.add(activity);
                          } else {
                            excluded.remove(activity);
                          }
                          _edit(
                              SupportSuggestionChoices(
                                  onlyWhenAsked: choices.onlyWhenAsked,
                                  excluded: excluded),
                              choices,
                              displayedEpoch);
                        }),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Save these choices on this device'),
                subtitle: const Text(
                    'Encrypted locally. No writing, feedback or mood history is included. You can review or forget them here.'),
                value: _approved,
                onChanged: _busy
                    ? null
                    : (value) {
                        if (_private &&
                            displayedEpoch == _epoch &&
                            identical(choices, _choices)) {
                          setState(() => _approved = value ?? false);
                        }
                      }),
            FilledButton(
                onPressed: _private && _approved && !_busy ? _save : null,
                child: const Text('Save suggestion choices')),
          ],
          const SizedBox(height: 12),
          TextButton(
              onPressed: _active && !_busy ? _forget : null,
              child: const Text('Forget suggestion choices')),
        ]),
      ))),
    ));
  }
}
