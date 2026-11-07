import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constitution/neura_constitution_service.dart';
import '../../intent_compiler/neura_action_graph.dart';
import '../../reliability/safe_boot.dart';
import '../models/clinic_contact_draft.dart';

/// Clinic contact remains on hold pending an explicit maintainer decision.
/// Normal construction never mounts the retained preparation workflow.
class ClinicContactScreen extends StatelessWidget {
  const ClinicContactScreen({super.key}) : _previewForTesting = false;

  /// Keeps synthetic regression coverage of the deferred implementation.
  /// This constructor cannot enable the workflow in profile or release builds.
  @visibleForTesting
  const ClinicContactScreen.previewForTesting({super.key})
      : _previewForTesting = true;

  final bool _previewForTesting;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode && _previewForTesting) {
      return const _ClinicContactPreview();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Doctor & clinic')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Clinic contact is on hold. '
            'Preparing clinic drafts and opening clinic portals or phone apps '
            'from this workflow are unavailable.'),
      ),
    );
  }
}

/// Local preparation and explicitly approved OS handoff only. No clinic API,
/// phone audio, model, private-store read, persistence or automatic send.
class _ClinicContactPreview extends StatefulWidget {
  const _ClinicContactPreview();

  @override
  State<_ClinicContactPreview> createState() => _ClinicContactPreviewState();
}

class _ClinicContactPreviewState extends State<_ClinicContactPreview>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _person = TextEditingController();
  final _clinic = TextEditingController();
  final _destination = TextEditingController();
  final _notes = TextEditingController();
  ClinicContactChannel _channel = ClinicContactChannel.portal;
  ClinicContactPurpose _purpose = ClinicContactPurpose.appointment;
  bool _checkedContact = false;
  bool _busy = false;
  int _epoch = 0;
  ClinicContactDraft? _draft;
  DialogRoute<bool>? _reviewRoute;
  Timer? _reviewTimer;
  String? _status;

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _currentRoute => ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_safeModeChanged);
    for (final controller in [_person, _clinic, _destination, _notes]) {
      controller.addListener(_edited);
    }
  }

  void _edited() {
    _dismissReview();
    setState(() {
      _epoch++;
      _checkedContact = false;
      _draft = null;
      _status = null;
    });
  }

  void _clear() {
    _epoch++;
    _dismissReview();
    for (final controller in [_person, _clinic, _destination, _notes]) {
      controller.clear();
    }
    setState(() {
      _draft = null;
      _checkedContact = false;
      _status = 'Temporary clinic details and draft cleared.';
    });
  }

  void _dismissReview({bool afterUnmount = false}) {
    _reviewTimer?.cancel();
    _reviewTimer = null;
    final route = _reviewRoute;
    _reviewRoute = null;
    if (route == null) return;
    void removeReview() {
      final navigator = route.navigator;
      if (navigator != null && navigator.mounted && route.isActive) {
        navigator.removeRoute(route);
      }
    }

    if (afterUnmount) {
      // Disposal may run while the navigator/overlay is locked. Remove only
      // this screen's review after unmount, before the next rendered frame.
      scheduleMicrotask(removeReview);
    } else {
      removeReview();
    }
  }

  void _safeModeChanged() {
    if (SafeBoot.instance.safeMode.value) _clear();
    if (mounted) setState(() => _epoch++);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _epoch++;
      _dismissReview();
    }
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _clear();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _dismissReview(afterUnmount: true);
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_safeModeChanged);
    for (final controller in [_person, _clinic, _destination, _notes]) {
      controller.removeListener(_edited);
      controller.dispose();
    }
    super.dispose();
  }

  void _prepare() {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _epoch++;
      _draft = ClinicContactDraft(
        personName: _person.text,
        clinicName: _clinic.text,
        purpose: _purpose,
        notes: _notes.text,
        channel: _channel,
        destination: _destination.text,
      );
      _status = 'Prepared on this device. No clinic has been contacted.';
    });
  }

  String? _policyBlock() {
    if (SafeBoot.instance.safeMode.value) {
      return 'Safe Mode blocks external handoff. Local preparation is available.';
    }
    final decision = NeuraConstitutionService.instance.current.evaluateEffect(
      effect: NeuraActionEffect.externalMessage,
      at: DateTime.now(),
      containsSensitiveContent: true,
    );
    return decision.allowed ? null : decision.reason;
  }

  Future<void> _reviewHandoff() async {
    final draft = _draft;
    if (_busy || draft == null || !_foreground || !_currentRoute) return;
    final uri = draft.handoffUri;
    if (uri == null || !_checkedContact) return;
    final epoch = _epoch;
    var operationEpoch = epoch;
    setState(() => _busy = true);
    try {
      // Loading is required: an uninitialized policy must never permit a link.
      await NeuraConstitutionService.instance.load();
      if (!mounted || epoch != _epoch || !_foreground || !_currentRoute) return;
      final blocked = _policyBlock();
      if (blocked != null) {
        setState(() =>
            _status = '$blocked Check your Personal Constitution settings.');
        return;
      }
      final expires = DateTime.now().add(const Duration(minutes: 2));
      final phone = draft.channel == ClinicContactChannel.phone;
      final review = DialogRoute<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(phone ? 'Review phone handoff' : 'Review portal handoff'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Clinic: ${draft.clinicName.trim()}'),
                Text('For: ${draft.personName.trim()}'),
                Text('Destination: $uri'),
                const SizedBox(height: 12),
                Text(draft.message),
                const SizedBox(height: 12),
                Text(phone
                    ? 'Only this phone number is passed to your phone app. '
                        'Your phone app may place a call immediately. You speak; '
                        'Neura does not join or send this brief.'
                    : 'Only this address is passed to your browser. The portal '
                        'receives a normal web visit. No name, notes or message '
                        'are attached. Sign in and send the message yourself.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(phone ? 'Open phone app' : 'Open clinic portal'),
            ),
          ],
        ),
      );
      _reviewRoute = review;
      _reviewTimer = Timer(const Duration(minutes: 2), () {
        _epoch++;
        _dismissReview();
        if (mounted) {
          setState(() => _status =
              'Review expired. Review the handoff again to continue.');
        }
      });
      final approved =
          await Navigator.of(context, rootNavigator: true).push(review);
      if (identical(_reviewRoute, review)) _reviewRoute = null;
      _reviewTimer?.cancel();
      _reviewTimer = null;
      if (!mounted ||
          approved != true ||
          epoch != _epoch ||
          !_foreground ||
          !_currentRoute ||
          !DateTime.now().isBefore(expires) ||
          _policyBlock() != null) {
        return;
      }
      // Consume this preview before invoking the platform. No retry, fallback
      // or delayed callback can reuse its approval.
      _epoch++;
      operationEpoch = _epoch;
      setState(
          () => _status = 'Opening external app. Delivery is not confirmed.');
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted || epoch + 1 != _epoch || !_foreground) return;
      setState(() => _status = opened
          ? 'External app opened. No clinic response or delivery is confirmed.'
          : 'Could not open an external app. Nothing was sent by Neura.');
    } catch (_) {
      if (mounted && operationEpoch == _epoch && _foreground) {
        setState(() => _status =
            'Handoff could not be confirmed. Neura has not sent a message.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = _channel == ClinicContactChannel.phone;
    final draft = _draft;
    return Scaffold(
      appBar: AppBar(title: const Text('Doctor & clinic')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Prepare a message or call brief for your own care team. '
              'Only details you type here are included. This temporary draft '
              'is cleared when you leave this screen or background the app.',
            ),
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Direct clinic messaging and Neura speaking on phone calls '
                  'are not connected yet. You can open your clinic portal or '
                  'phone app after review. Neura does not provide diagnosis, '
                  'treatment or emergency monitoring. For urgent help, contact '
                  'local emergency services directly.',
                ),
              ),
            ),
            _field(_person, 'Your name', 100),
            _field(_clinic, 'Doctor or clinic name', 150),
            const SizedBox(height: 12),
            DropdownButtonFormField<ClinicContactPurpose>(
              initialValue: _purpose,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Purpose'),
              items: ClinicContactPurpose.values
                  .map((purpose) => DropdownMenuItem(
                        value: purpose,
                        child: Text(purpose.label),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                _purpose = value;
                _edited();
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final channel in ClinicContactChannel.values)
                  ChoiceChip(
                    label: Text(channel == ClinicContactChannel.phone
                        ? 'Phone call brief'
                        : 'Portal message'),
                    selected: _channel == channel,
                    onSelected: (_) {
                      _channel = channel;
                      _checkedContact = false;
                      _destination.clear();
                      _edited();
                    },
                  ),
              ],
            ),
            _field(
              _destination,
              phone ? 'Clinic phone number' : 'Clinic portal HTTPS address',
              300,
              keyboard: phone ? TextInputType.phone : TextInputType.url,
              validator: (value) => (phone
                          ? ClinicContactDraft.phoneUri(value ?? '')
                          : ClinicContactDraft.portalUri(value ?? '')) ==
                      null
                  ? phone
                      ? 'Use 7–15 digits, without extensions or dial commands.'
                      : 'Use the HTTPS sign-in address, without a query, fragment or login details.'
                  : null,
            ),
            _field(_notes, 'What I want my care team to know', 4000, lines: 5),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _checkedContact,
              onChanged: (value) {
                setState(() {
                  _checkedContact = value ?? false;
                  _epoch++;
                });
              },
              title: const Text(
                  'I checked this contact using my clinic’s own information.'),
              subtitle: const Text(
                  'Neura has not verified the clinic or your patient identity.'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _prepare,
              icon: const Icon(Icons.edit_note),
              label: const Text('Prepare locally'),
            ),
            if (draft != null) ...[
              const SizedBox(height: 16),
              Text(phone ? 'My call brief' : 'My portal message',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SelectableText(draft.message),
              const SizedBox(height: 8),
              Text(phone
                  ? 'Keep this brief nearby when you call.'
                  : 'You can select and copy this text yourself. Your system '
                      'clipboard may be accessible to other apps or synced devices. '
                      'Paste and review it in the clinic portal yourself.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ||
                        !_checkedContact ||
                        SafeBoot.instance.safeMode.value
                    ? null
                    : _reviewHandoff,
                icon: Icon(phone ? Icons.phone_outlined : Icons.open_in_new),
                label: const Text('Review external handoff'),
              ),
            ],
            if (SafeBoot.instance.safeMode.value)
              const Text('Safe Mode: external handoff is disabled.'),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_status!, semanticsLabel: _status),
              ),
            TextButton(
              onPressed: _clear,
              child: const Text('Clear temporary details'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, int limit,
      {int lines = 1,
      TextInputType? keyboard,
      FormFieldValidator<String>? validator}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextFormField(
        controller: controller,
        maxLength: limit,
        maxLines: lines,
        keyboardType: keyboard,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        autocorrect: false,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        validator: validator ??
            (value) =>
                value == null || value.trim().isEmpty ? 'Enter $label.' : null,
      ),
    );
  }
}
