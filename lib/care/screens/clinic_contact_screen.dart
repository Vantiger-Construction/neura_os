import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constitution/neura_constitution_service.dart';
import '../../intent_compiler/neura_action_graph.dart';
import '../../modules/mood/mood_models.dart';
import '../../modules/mood/mood_store.dart';
import '../../modules/support/support_page_shortcuts.dart';
import '../../reliability/safe_boot.dart';
import '../models/clinic_contact_draft.dart';
import '../models/clinic_report.dart';
import '../services/clinic_contact_route_observer.dart';

enum _ClinicAction { copy, save, handoff }

/// Patient-controlled preparation, report export and reviewed OS handoff.
/// No direct clinic transport, call audio, model or automatic submission.
class ClinicContactScreen extends StatefulWidget {
  const ClinicContactScreen(
      {super.key, this.loadCheckIns, this.copyReport, this.saveReport});

  @visibleForTesting
  const ClinicContactScreen.previewForTesting(
      {super.key, this.loadCheckIns, this.copyReport, this.saveReport});

  final Future<List<MoodEntry>> Function()? loadCheckIns;
  final Future<void> Function(String)? copyReport;
  final Future<Uri?> Function(Uint8List)? saveReport;

  @override
  State<ClinicContactScreen> createState() => _ClinicContactScreenState();
}

class _ClinicContactScreenState extends State<ClinicContactScreen>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _person = TextEditingController();
  final _clinic = TextEditingController();
  final _doctor = TextEditingController();
  final _destination = TextEditingController();
  final _notes = TextEditingController();
  final _clientInstructions = TextEditingController();
  final _report = TextEditingController();
  List<MoodEntry> _entries = [];
  final _selected = <int>{};
  bool _includeNotes = false;
  ClinicContactChannel _channel = ClinicContactChannel.portal;
  ClinicContactPurpose _purpose = ClinicContactPurpose.appointment;
  bool _checkedContact = false;
  bool _allowReportExport = false;
  bool _allowContactHandoff = false;
  bool _busy = false;
  bool _updatingControllers = false;
  List<String> _inputValues = ['', '', '', '', '', ''];
  String _reportValue = '';
  int _epoch = 0;
  int _editorGeneration = 0;
  ClinicContactDraft? _draft;
  ModalRoute<dynamic>? _route;
  DialogRoute<bool>? _reviewRoute;
  Timer? _reviewTimer;
  String? _status;

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _tracked => identical(
      clinicContactRouteObserver.navigator, Navigator.maybeOf(context));
  bool get _mayPrepare =>
      mounted &&
      _foreground &&
      _tracked &&
      _route?.isCurrent == true &&
      !SafeBoot.instance.restartRequired.value;
  bool _current(int epoch) => _mayPrepare && epoch == _epoch;

  VoidCallback _guarded(int epoch, VoidCallback action) => () {
        if (_current(epoch) && !_busy) {
          action();
        }
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_safetyChanged);
    SafeBoot.instance.restartRequired.addListener(_safetyChanged);
    NeuraConstitutionService.instance.revision.addListener(_policyChanged);
    clinicContactRouteObserver.addListener(_topChanged);
    for (final controller in [
      _person,
      _clinic,
      _doctor,
      _destination,
      _notes,
      _clientInstructions
    ]) {
      controller.addListener(_typedEdited);
    }
    _report.addListener(_reportEdited);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  void _topChanged(Route<dynamic> top) {
    if (_route != null && top != _route && top != _reviewRoute) {
      _clear(deferReviewRemoval: true);
    }
  }

  void _edited() {
    if (_updatingControllers) return;
    _dismissReview();
    setState(() {
      _epoch++;
      _checkedContact = false;
      _allowReportExport = false;
      _allowContactHandoff = false;
      _draft = null;
      _updatingControllers = true;
      _report.clear();
      _reportValue = '';
      _updatingControllers = false;
      _status = null;
    });
  }

  void _typedEdited() {
    if (_updatingControllers) return;
    final values = [
      _person.text,
      _clinic.text,
      _doctor.text,
      _destination.text,
      _notes.text,
      _clientInstructions.text
    ];
    if (listEquals(values, _inputValues)) return;
    _inputValues = values;
    _edited();
  }

  void _reportEdited() {
    if (_updatingControllers || _report.text == _reportValue) return;
    _reportValue = _report.text;
    _dismissReview();
    setState(() {
      _epoch++;
      _allowReportExport = false;
      _allowContactHandoff = false;
      _status = null;
    });
  }

  void _clear({bool deferReviewRemoval = false}) {
    if (!mounted) return;
    _epoch++;
    _editorGeneration++;
    _dismissReview(deferred: deferReviewRemoval);
    _updatingControllers = true;
    for (final controller in [
      _person,
      _clinic,
      _doctor,
      _destination,
      _notes,
      _clientInstructions,
      _report
    ]) {
      controller.clear();
    }
    _inputValues = ['', '', '', '', '', ''];
    _reportValue = '';
    _updatingControllers = false;
    setState(() {
      _entries = [];
      _selected.clear();
      _includeNotes = false;
      _draft = null;
      _checkedContact = false;
      _allowReportExport = false;
      _allowContactHandoff = false;
      _status = 'Temporary clinic details and draft cleared.';
    });
  }

  void _dismissReview({bool deferred = false}) {
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

    if (deferred) {
      scheduleMicrotask(removeReview);
    } else {
      removeReview();
    }
  }

  void _safetyChanged() => _clear();

  void _policyChanged() {
    if (!mounted) return;
    _epoch++;
    _dismissReview();
    setState(() {
      _allowReportExport = false;
      _allowContactHandoff = false;
      _status = 'Sharing policy changed. Review your permissions again.';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _clear();
    } else if (mounted) {
      // Re-enable a blank editor without restoring a report or approval.
      setState(() {});
    }
  }

  @override
  void dispose() {
    _epoch++;
    _dismissReview(deferred: true);
    clinicContactRouteObserver.removeListener(_topChanged);
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_safetyChanged);
    SafeBoot.instance.restartRequired.removeListener(_safetyChanged);
    NeuraConstitutionService.instance.revision.removeListener(_policyChanged);
    for (final controller in [
      _person,
      _clinic,
      _doctor,
      _destination,
      _notes,
      _clientInstructions
    ]) {
      controller.removeListener(_typedEdited);
      controller.dispose();
    }
    _report.removeListener(_reportEdited);
    _report.dispose();
    super.dispose();
  }

  Future<void> _loadCheckIns() async {
    if (!_mayPrepare || _busy || SafeBoot.instance.safeMode.value) return;
    _edited();
    final epoch = _epoch;
    setState(() {
      _busy = true;
      _entries = [];
      _selected.clear();
      _includeNotes = false;
    });
    try {
      final entries = await (widget.loadCheckIns ?? MoodStore.instance.getAll)()
          .timeout(const Duration(seconds: 8));
      if (!_current(epoch) || SafeBoot.instance.safeMode.value) return;
      final now = DateTime.now();
      final valid = entries
          .where((entry) =>
              !entry.timestamp.isAfter(now) &&
              entry.mood0to10 >= 0 &&
              entry.mood0to10 <= 10)
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      setState(() {
        _entries = valid.take(30).toList();
        _status = _entries.isEmpty
            ? 'No saved check-ins available. You can still prepare your report.'
            : 'Choose the check-ins to include. None are selected for you.';
      });
    } catch (_) {
      if (_current(epoch)) {
        setState(() => _status =
            'Check-ins could not be opened. You can still type your report.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _prepare() {
    if (!_mayPrepare || _busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    try {
      final draft = ClinicContactDraft(
        personName: _person.text,
        clinicName: _clinic.text,
        purpose: _purpose,
        notes: _notes.text,
        channel: _channel,
        destination: _destination.text,
        doctorName: _doctor.text,
        clientInstructions: _clientInstructions.text,
      );
      final report = clinicReport(
        draft: draft,
        selected: [for (final i in _selected.toList()..sort()) _entries[i]],
        includeNotes: _includeNotes,
        preparedAt: DateTime.now(),
      );
      setState(() {
        _epoch++;
        _allowReportExport = false;
        _allowContactHandoff = false;
        _draft = draft;
        _updatingControllers = true;
        _report.text = report;
        _reportValue = report;
        _updatingControllers = false;
        _status = 'Prepared on this device. No clinic has been contacted.';
      });
    } on FormatException catch (error) {
      setState(() => _status = error.message);
    }
  }

  String? _policyBlock() {
    if (SafeBoot.instance.safeMode.value) {
      return 'Safe Mode blocks export and external handoff.';
    }
    if (SafeBoot.instance.restartRequired.value) {
      return 'Recovery requires a restart before sharing.';
    }
    final decision = NeuraConstitutionService.instance.current.evaluateEffect(
      effect: NeuraActionEffect.externalMessage,
      at: DateTime.now(),
      containsSensitiveContent: true,
    );
    return decision.allowed ? null : decision.reason;
  }

  bool _permitted(_ClinicAction action) => switch (action) {
        _ClinicAction.copy || _ClinicAction.save => _allowReportExport,
        _ClinicAction.handoff => _allowContactHandoff,
      };

  void _changePermission(int epoch, {bool? export, bool? handoff}) {
    if (!_current(epoch) || _busy) return;
    _dismissReview();
    setState(() {
      _epoch++;
      if (export != null) _allowReportExport = export;
      if (handoff != null) _allowContactHandoff = handoff;
      _status = null;
    });
  }

  Future<void> _reviewAction(_ClinicAction action) async {
    final draft = _draft;
    final text = _report.text;
    if (_busy ||
        draft == null ||
        !_permitted(action) ||
        !_mayPrepare ||
        text.trim().isEmpty ||
        text.length > 12000) {
      return;
    }
    final uri = draft.handoffUri;
    if (action == _ClinicAction.handoff && (uri == null || !_checkedContact)) {
      return;
    }
    final epoch = _epoch;
    var operationEpoch = epoch;
    setState(() => _busy = true);
    try {
      await NeuraConstitutionService.instance
          .load()
          .timeout(const Duration(seconds: 8));
      if (!_current(epoch) || !_permitted(action) || _report.text != text) {
        return;
      }
      final blocked = _policyBlock();
      if (blocked != null) {
        setState(() =>
            _status = '$blocked Check your Personal Constitution settings.');
        return;
      }
      final issued = DateTime.now();
      final expires = issued.add(const Duration(minutes: 2));
      final phone = draft.channel == ClinicContactChannel.phone;
      final label = switch (action) {
        _ClinicAction.copy => 'Copy reviewed report',
        _ClinicAction.save => 'Save reviewed text file',
        _ClinicAction.handoff =>
          phone ? 'Open phone app' : 'Open clinic portal',
      };
      final explanation = switch (action) {
        _ClinicAction.copy => 'Only the exact report below is copied. '
            'Your clipboard may be accessible to other apps or synced devices. '
            'Sign in to your clinic portal, paste and review it there yourself.',
        _ClinicAction.save => 'Only the exact report below is handed to the '
            'system save dialog as a UTF-8 text file. Choose where to save it. '
            'This file is unencrypted and may be synced by that location. '
            'Once handed to the system, saving may finish after Neura closes. '
            'Neura cannot retract it or remove it with an app data wipe.',
        _ClinicAction.handoff => phone
            ? 'Only this phone number is passed to your phone app. '
                'Your phone app may place a call immediately. You speak; '
                'Neura does not join or send this brief.'
            : 'Only this address is passed to your browser. The portal '
                'receives a normal web visit. No name, notes or message '
                'are attached. Sign in and send the message yourself.',
      };
      late final DialogRoute<bool> review;
      review = DialogRoute<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(action == _ClinicAction.handoff
              ? phone
                  ? 'Review phone handoff'
                  : 'Review portal handoff'
              : 'Review report export'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Clinic: ${draft.clinicName.trim()}'),
                if (draft.doctorName.trim().isNotEmpty)
                  Text('Doctor: ${draft.doctorName.trim()}'),
                Text('For: ${draft.personName.trim()}'),
                Text(action == _ClinicAction.handoff
                    ? 'Client permission: open this portal or phone app only.'
                    : 'Client permission: copy or save this reviewed report only.'),
                if (draft.clientInstructions.trim().isNotEmpty)
                  Text(
                      'Client instructions: ${draft.clientInstructions.trim()}'),
                if (action == _ClinicAction.handoff) Text('Destination: $uri'),
                const SizedBox(height: 12),
                Text(text),
                const SizedBox(height: 12),
                Text(explanation),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (review.isCurrent && identical(_reviewRoute, review)) {
                  Navigator.of(dialogContext).pop(false);
                }
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (mounted &&
                    epoch == _epoch &&
                    _foreground &&
                    review.isCurrent &&
                    identical(_reviewRoute, review)) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: Text(label),
            ),
          ],
        ),
      );
      _reviewRoute = review;
      _reviewTimer = Timer(const Duration(minutes: 2), () {
        _epoch++;
        _dismissReview();
        if (mounted) {
          setState(() =>
              _status = 'Review expired. Review the action again to continue.');
        }
      });
      final approved =
          await Navigator.of(context, rootNavigator: true).push(review);
      if (identical(_reviewRoute, review)) _reviewRoute = null;
      _reviewTimer?.cancel();
      _reviewTimer = null;
      final now = DateTime.now();
      if (approved != true ||
          !_current(epoch) ||
          !_permitted(action) ||
          _report.text != text ||
          now.isBefore(issued) ||
          !now.isBefore(expires) ||
          _policyBlock() != null) {
        return;
      }
      // Consume the exact-content approval before invoking any OS operation.
      // An already-dispatched clipboard, file or link cannot be retracted.
      _epoch++;
      operationEpoch = _epoch;
      setState(() => _status = 'Handing off your reviewed action…');
      final String status;
      switch (action) {
        case _ClinicAction.copy:
          await (widget.copyReport ??
              (value) => Clipboard.setData(ClipboardData(text: value)))(text);
          status = 'Report copied. Paste and review it in your clinic portal. '
              'Nothing was sent by Neura.';
        case _ClinicAction.save:
          final bytes = Uint8List.fromList(utf8.encode(text));
          final saved = await (widget.saveReport ??
              (bytes) => FilePicker.saveFile(
                    fileName: 'neura-clinic-report.txt',
                    mimeType: 'text/plain',
                    bytes: bytes,
                  ))(bytes);
          status = saved == null
              ? 'Save cancelled. Neura has no saved-file confirmation.'
              : 'Report saved to your chosen location. Nothing was sent to a clinic.';
        case _ClinicAction.handoff:
          final opened =
              await launchUrl(uri!, mode: LaunchMode.externalApplication);
          status = opened
              ? 'External app opened. No clinic response or delivery is confirmed.'
              : 'Could not open an external app. Nothing was sent by Neura.';
      }
      if (!_current(operationEpoch)) return;
      setState(() => _status = status);
    } catch (_) {
      if (_current(operationEpoch)) {
        setState(() => _status =
            'This action could not be confirmed. Check your clipboard, '
                'chosen file location or external app before trying again. '
                'No clinic delivery is confirmed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = _channel == ClinicContactChannel.phone;
    final draft = _draft;
    final displayedEpoch = _epoch;
    final canEdit = _mayPrepare && !_busy;
    final mayExport = canEdit &&
        !SafeBoot.instance.safeMode.value &&
        draft != null &&
        _report.text.trim().isNotEmpty &&
        _report.text.length <= 12000;
    return SupportPageShortcuts(
      child: Scaffold(
        appBar: AppBar(title: const Text('Doctor & clinic'), actions: [
          IconButton(
              tooltip: 'Stop and clear clinic report',
              onPressed: _clear,
              icon: const Icon(Icons.stop_circle_outlined)),
        ]),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('Prepare a report for your own care team. Only '
                        'what you type and the check-ins you select are included. '
                        'Your journal, chats and companion memories stay closed. '
                        'Leaving this screen or app clears this temporary draft.'),
                    const SizedBox(height: 12),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                            'Direct clinic messaging and Neura speaking '
                            'on phone calls are not connected yet. You can copy '
                            'or save your reviewed report and open your clinic '
                            'portal or phone app. Sign in and send it yourself. '
                            'This is not emergency monitoring or medical advice.'),
                      ),
                    ),
                    Text('Client and doctor details',
                        style: Theme.of(context).textTheme.titleMedium),
                    _field(_person, 'Client full name', 100),
                    _field(_clinic, 'Clinic or practice name', 150),
                    _field(_doctor, 'Doctor name (optional)', 150,
                        validator: (_) => null),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ClinicContactPurpose>(
                      initialValue: _purpose,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Purpose'),
                      items: ClinicContactPurpose.values
                          .map((purpose) => DropdownMenuItem(
                              value: purpose, child: Text(purpose.label)))
                          .toList(),
                      onChanged: !canEdit
                          ? null
                          : (value) {
                              if (value == null || !_current(displayedEpoch)) {
                                return;
                              }
                              _purpose = value;
                              _edited();
                            },
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, children: [
                      for (final channel in ClinicContactChannel.values)
                        ChoiceChip(
                          label: Text(channel == ClinicContactChannel.phone
                              ? 'Phone call brief'
                              : 'Portal message'),
                          selected: _channel == channel,
                          onSelected: !canEdit
                              ? null
                              : (_) {
                                  if (!_current(displayedEpoch)) return;
                                  _channel = channel;
                                  _destination.clear();
                                  _edited();
                                },
                        ),
                    ]),
                    _field(
                      _destination,
                      phone
                          ? 'Clinic phone number'
                          : 'Clinic portal HTTPS address',
                      300,
                      keyboard: phone ? TextInputType.phone : TextInputType.url,
                      validator: (value) => (phone
                                  ? ClinicContactDraft.phoneUri(value ?? '')
                                  : ClinicContactDraft.portalUri(
                                      value ?? '')) ==
                              null
                          ? phone
                              ? 'Use 7–15 digits, without extensions or dial commands.'
                              : 'Use the HTTPS sign-in address, without a query, fragment or login details.'
                          : null,
                    ),
                    _field(_notes, 'What I want my care team to know', 4000,
                        lines: 5),
                    _field(
                        _clientInstructions,
                        'Client sharing instructions or limits (optional)',
                        1000,
                        lines: 2,
                        validator: (_) => null),
                    const Text('These instructions are included in your draft '
                        'for you to check. They do not authorize an action or '
                        'give Neura access to clinic records.'),
                    OutlinedButton(
                      onPressed: canEdit && !SafeBoot.instance.safeMode.value
                          ? _guarded(displayedEpoch, _loadCheckIns)
                          : null,
                      child: const Text('Choose saved check-ins (optional)'),
                    ),
                    if (_entries.isNotEmpty) ...[
                      const Text('Choose up to ten of your latest thirty '
                          'check-ins. None are selected automatically.'),
                      for (var i = 0; i < _entries.length; i++)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          key: ValueKey('clinic-check-in-$i'),
                          title: Text('${_entries[i].timestamp.toLocal()} · '
                              'Mood ${_entries[i].mood0to10}/10'),
                          value: _selected.contains(i),
                          onChanged: !canEdit ||
                                  (_selected.length >= 10 &&
                                      !_selected.contains(i))
                              ? null
                              : (value) {
                                  if (!_current(displayedEpoch)) return;
                                  if (value == true) {
                                    _selected.add(i);
                                  } else {
                                    _selected.remove(i);
                                  }
                                  _edited();
                                },
                        ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title:
                            const Text('Include notes from selected check-ins'),
                        subtitle: const Text('Optional. At most 500 characters '
                            'per note; shortened notes are marked.'),
                        value: _includeNotes,
                        onChanged: !canEdit
                            ? null
                            : (value) {
                                if (!_current(displayedEpoch)) return;
                                _includeNotes = value ?? false;
                                _edited();
                              },
                      ),
                    ],
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _checkedContact,
                      onChanged: !canEdit
                          ? null
                          : (value) {
                              if (!_current(displayedEpoch)) return;
                              setState(() {
                                _checkedContact = value ?? false;
                                _epoch++;
                              });
                            },
                      title:
                          const Text('I checked this contact using my clinic’s '
                              'own information.'),
                      subtitle: const Text('Neura has not verified the clinic '
                          'or your patient identity.'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          canEdit ? _guarded(displayedEpoch, _prepare) : null,
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Prepare locally'),
                    ),
                    if (draft != null) ...[
                      const SizedBox(height: 16),
                      TextField(
                        key: ValueKey('clinic-report-$_editorGeneration'),
                        controller: _report,
                        minLines: 5,
                        maxLines: null,
                        maxLength: 12000,
                        enabled: canEdit,
                        enableInteractiveSelection: false,
                        enableSuggestions: false,
                        enableIMEPersonalizedLearning: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                            labelText: 'Editable clinic report',
                            border: OutlineInputBorder()),
                      ),
                      const Text('Edit or remove any part. Every export needs '
                          'fresh review of the exact text. A copied report '
                          'may remain in your system clipboard.'),
                      const Text('Standard field selection and cut/copy/paste '
                          'shortcuts are disabled here. Use Review copy to '
                          'export your report.'),
                      Card(
                        child: Column(children: [
                          ListTile(
                            title: Text('Client permissions',
                                style: Theme.of(context).textTheme.titleMedium),
                            subtitle: const Text('Choose only the actions you '
                                'want for this report. Permissions start off, '
                                'last for this screen, and reset when details '
                                'or report text change.'),
                          ),
                          CheckboxListTile(
                            key: const ValueKey('clinic-permission-export'),
                            value: _allowReportExport,
                            title: const Text(
                                'Allow copying or saving my reviewed report'),
                            subtitle: const Text(
                                'The exact text still needs my approval each time.'),
                            onChanged: canEdit
                                ? (value) => _changePermission(displayedEpoch,
                                    export: value ?? false)
                                : null,
                          ),
                          CheckboxListTile(
                            key: const ValueKey('clinic-permission-handoff'),
                            value: _allowContactHandoff,
                            title: const Text(
                                'Allow opening my doctor’s portal or phone app'),
                            subtitle:
                                const Text('This does not send my report or '
                                    'let Neura speak on a call.'),
                            onChanged: canEdit
                                ? (value) => _changePermission(displayedEpoch,
                                    handoff: value ?? false)
                                : null,
                          ),
                        ]),
                      ),
                      OutlinedButton.icon(
                        onPressed: mayExport && _allowReportExport
                            ? _guarded(displayedEpoch,
                                () => _reviewAction(_ClinicAction.copy))
                            : null,
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Review copy'),
                      ),
                      OutlinedButton.icon(
                        onPressed: mayExport && _allowReportExport
                            ? _guarded(displayedEpoch,
                                () => _reviewAction(_ClinicAction.save))
                            : null,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('Review text export'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            mayExport && _checkedContact && _allowContactHandoff
                                ? _guarded(displayedEpoch,
                                    () => _reviewAction(_ClinicAction.handoff))
                                : null,
                        icon: Icon(
                            phone ? Icons.phone_outlined : Icons.open_in_new),
                        label: const Text('Review external handoff'),
                      ),
                    ],
                    if (SafeBoot.instance.safeMode.value)
                      const Text('Safe Mode: external handoff is disabled. '
                          'Saved check-ins and report export are disabled too.'),
                    if (SafeBoot.instance.restartRequired.value)
                      const Text(
                          'Restart Neura before preparing another report.'),
                    if (_status != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child:
                            Semantics(liveRegion: true, child: Text(_status!)),
                      ),
                    TextButton(
                      onPressed: _clear,
                      child: const Text('Clear temporary details'),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
        key: ValueKey('$label-$_editorGeneration'),
        controller: controller,
        enabled: _mayPrepare && !_busy,
        enableInteractiveSelection: false,
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
