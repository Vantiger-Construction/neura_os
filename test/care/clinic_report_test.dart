import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/care/models/clinic_contact_draft.dart';
import 'package:neuro_companion/care/models/clinic_report.dart';
import 'package:neuro_companion/care/screens/clinic_contact_screen.dart';
import 'package:neuro_companion/care/services/clinic_contact_route_observer.dart';
import 'package:neuro_companion/constitution/neura_constitution_service.dart';
import 'package:neuro_companion/constitution/neura_personal_constitution.dart';
import 'package:neuro_companion/modules/mood/mood_models.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder reportField() => find.byWidgetPredicate((widget) =>
    widget is TextField &&
    widget.decoration?.labelText == 'Editable clinic report');

String reportText(WidgetTester tester) =>
    tester.widget<TextField>(reportField()).controller!.text;

const draft = ClinicContactDraft(
  personName: 'Alex Example',
  clinicName: 'Example Clinic',
  purpose: ClinicContactPurpose.followUp,
  notes: 'My own question',
  channel: ClinicContactChannel.portal,
  destination: 'https://clinic.example.test/login',
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final copies = <String>[];
  final files = <String>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() async {
    copies.clear();
    files.clear();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await NeuraPrefsCache.prefs.clear();
    NeuraConstitutionService.instance.resetAfterDataWipe();
    await NeuraConstitutionService.instance
        .save(const NeuraPersonalConstitution(allowExternalMessages: true));
  });

  Future<void> allowReport(WidgetTester tester) async {
    final permission = find.byKey(const ValueKey('clinic-permission-export'));
    await tester.scrollUntilVisible(permission, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    if (!tester.widget<CheckboxListTile>(permission).value!) {
      await tester.tap(permission);
      await tester.pumpAndSettle();
    }
  }

  Future<void> mount(WidgetTester tester,
      {Future<List<MoodEntry>> Function()? load,
      Future<void> Function(String)? copy,
      Future<Uri?> Function(Uint8List)? save,
      bool cancelSave = false,
      bool allowExport = true}) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [clinicContactRouteObserver],
      home: ClinicContactScreen(
        loadCheckIns: load ?? () async => [],
        copyReport: copy ?? (text) async => copies.add(text),
        saveReport: save ?? (bytes) async {
          if (cancelSave) return null;
          files.add(utf8.decode(bytes));
          return Uri.file('/synthetic/neura-clinic-report.txt');
        },
      ),
    ));
    await tester.pumpAndSettle();
    for (final (index, text) in [
      'Alex Example',
      'Example Clinic',
      '',
      'https://clinic.example.test/login',
      'My own question',
      ''
    ].indexed) {
      await tester.enterText(find.byType(TextFormField).at(index), text);
    }
    await tester.pump();
    await tester.tap(find.text('Prepare locally'));
    await tester.pumpAndSettle();
    if (allowExport) await allowReport(tester);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.pump();
    if (find.text(label).evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(find.text(label), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  test('report includes only selected self-reports and optional notes', () {
    final checkIn = MoodEntry(
        timestamp: DateTime(2026, 1, 2),
        mood0to10: 6,
        note: 'SELECTED-NOTE',
        energy0to10: 4,
        sleepHours: 7);
    final text = clinicReport(
        draft: draft,
        selected: [checkIn],
        includeNotes: false,
        preparedAt: DateTime(2026, 1, 3));
    expect(text, contains('From: Alex Example'));
    expect(text, contains('Check-ins I chose to include (1)'));
    expect(text, contains('mood 6/10; energy 4/10; sleep 7.0 hours'));
    expect(text, isNot(contains('SELECTED-NOTE')));
    expect(text, contains('self-reports, not a diagnosis'));
    final withNotes = clinicReport(
        draft: draft,
        selected: [checkIn],
        includeNotes: true,
        preparedAt: DateTime(2026, 1, 3));
    expect(withNotes, contains('SELECTED-NOTE'));
    expect(
        () => clinicReport(
            draft: draft,
            selected: List.filled(11, checkIn),
            includeNotes: false,
            preparedAt: DateTime(2026, 1, 3)),
        throwsFormatException);
  });

  testWidgets(
      'saved history needs a click and nothing is selected automatically',
      (tester) async {
    var reads = 0;
    await mount(tester, load: () async {
      reads++;
      return [
        MoodEntry(
            timestamp: DateTime(2025, 1, 1),
            mood0to10: 6,
            note: 'PRIVATE-NOTE'),
        MoodEntry(
            timestamp: DateTime(2025, 1, 2), mood0to10: 8, note: 'OTHER-NOTE'),
      ];
    });
    expect(reads, 0);
    expect(reportText(tester), contains('Check-ins I chose to include (0)'));
    await tap(tester, 'Choose saved check-ins (optional)');
    expect(reads, 1);
    expect(reportField(), findsNothing);
    await tap(tester, 'Prepare locally');
    expect(reportText(tester), contains('Check-ins I chose to include (0)'));
    await tester.tap(find.byKey(const ValueKey('clinic-check-in-1')));
    await tester.pumpAndSettle();
    await tap(tester, 'Prepare locally');
    expect(reportText(tester), contains('Check-ins I chose to include (1)'));
    expect(reportText(tester), contains('mood 6/10'));
    expect(reportText(tester), isNot(contains('mood 8/10')));
    expect(reportText(tester), isNot(contains('PRIVATE-NOTE')));
    await tap(tester, 'Include notes from selected check-ins');
    await tap(tester, 'Prepare locally');
    expect(reportText(tester), contains('PRIVATE-NOTE'));
    expect(reportText(tester), isNot(contains('OTHER-NOTE')));
    expect(copies, isEmpty);
    expect(files, isEmpty);
  });

  testWidgets('copy sends only the exact edited Unicode report after approval',
      (tester) async {
    await mount(tester);
    const edited = 'My edited report — café 患者 🫶\nOnly this exact text.';
    await tester.enterText(reportField(), edited);
    await tester.pumpAndSettle();
    await allowReport(tester);
    await tap(tester, 'Review copy');
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text(edited)),
        findsOneWidget);
    expect(copies, isEmpty);
    await tester.tap(find.text('Copy reviewed report'));
    await tester.pumpAndSettle();
    expect(copies, [edited]);
    expect(files, isEmpty);
    await tap(tester, 'Review copy');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(copies, hasLength(1));
  });

  testWidgets(
      'file export contains the reviewed UTF-8 text and no extra record',
      (tester) async {
    await mount(tester);
    const edited = 'Patient-selected report: é 中文\nQuestion?';
    await tester.enterText(reportField(), edited);
    await tester.pumpAndSettle();
    await allowReport(tester);
    await tap(tester, 'Review text export');
    expect(files, isEmpty);
    expect(find.textContaining('This file is unencrypted'), findsOneWidget);
    await tester.tap(find.text('Save reviewed text file'));
    await tester.pumpAndSettle();
    expect(files, [edited]);
    expect(copies, isEmpty);
    expect(find.textContaining('Nothing was sent to a clinic'), findsOneWidget);
  });

  testWidgets('cancelled file picker never becomes saved or delivered',
      (tester) async {
    await mount(tester, cancelSave: true);
    await tap(tester, 'Review text export');
    await tester.tap(find.text('Save reviewed text file'));
    await tester.pumpAndSettle();
    expect(files, isEmpty);
    expect(find.textContaining('Save cancelled'), findsOneWidget);
    expect(find.textContaining('Report saved to'), findsNothing);
  });

  testWidgets(
      'editing during a review removes it and revokes a retained callback',
      (tester) async {
    await mount(tester);
    await tap(tester, 'Review copy');
    final confirm = tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Copy reviewed report'))
        .onPressed!;
    tester.widget<TextField>(reportField()).controller!.text =
        'CHANGED-AFTER-REVIEW';
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    confirm();
    await tester.pumpAndSettle();
    expect(copies, isEmpty);
    expect(files, isEmpty);
  });

  for (final save in [false, true]) {
    testWidgets(
        'policy revocation blocks an approved ${save ? 'file' : 'copy'}',
        (tester) async {
      await mount(tester);
      await tap(tester, save ? 'Review text export' : 'Review copy');
      final confirm = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton,
              save ? 'Save reviewed text file' : 'Copy reviewed report'))
          .onPressed!;
      await NeuraConstitutionService.instance
          .save(const NeuraPersonalConstitution());
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await NeuraConstitutionService.instance
          .save(const NeuraPersonalConstitution(allowExternalMessages: true));
      confirm();
      await tester.pumpAndSettle();
      expect(copies, isEmpty);
      expect(files, isEmpty);
    });
  }

  testWidgets('recovery removes the review and cannot resume after reset',
      (tester) async {
    await mount(tester);
    await tap(tester, 'Review text export');
    final confirm = tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save reviewed text file'))
        .onPressed!;
    SafeBoot.instance.restartRequired.value = true;
    await tester.pumpAndSettle();
    SafeBoot.instance.restartRequired.value = false;
    await tester.pumpAndSettle();
    confirm();
    await tester.pumpAndSettle();
    expect(reportField(), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(files, isEmpty);
  });

  testWidgets(
      'a late history load is discarded after route cover and immediate pop',
      (tester) async {
    final pending = Completer<List<MoodEntry>>();
    await mount(tester, load: () => pending.future);
    await tap(tester, 'Choose saved check-ins (optional)');
    final navigator =
        Navigator.of(tester.element(find.byType(ClinicContactScreen)));
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other route')))));
    navigator.pop();
    pending.complete([
      MoodEntry(
          timestamp: DateTime(2025, 1, 1),
          mood0to10: 6,
          note: 'LATE-PRIVATE-NOTE')
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('clinic-check-in-0')), findsNothing);
    expect(reportField(), findsNothing);
    expect(copies, isEmpty);
    expect(files, isEmpty);
  });

  testWidgets('a late clipboard completion cannot revive a stopped report',
      (tester) async {
    final pending = Completer<void>();
    await mount(tester, copy: (text) {
      copies.add(text);
      return pending.future;
    });
    await tap(tester, 'Review copy');
    await tester.tap(find.text('Copy reviewed report'));
    await tester.pumpAndSettle();
    expect(copies, hasLength(1));
    await tap(tester, 'Clear temporary details');
    pending.complete();
    await tester.pumpAndSettle();
    expect(reportField(), findsNothing);
    expect(find.textContaining('Report copied.'), findsNothing);
    expect(find.textContaining('Temporary clinic details'), findsOneWidget);
    expect(copies, hasLength(1));
  });

  testWidgets('cover and immediate pop revoke a retained report confirmation',
      (tester) async {
    await mount(tester);
    await tap(tester, 'Review copy');
    final confirm = tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Copy reviewed report'))
        .onPressed!;
    final navigator = clinicContactRouteObserver.navigator!;
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other route')))));
    navigator.pop();
    confirm();
    await tester.pumpAndSettle();
    expect(copies, isEmpty);
    expect(files, isEmpty);
    expect(reportField(), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale load button cannot reopen history after Stop',
      (tester) async {
    var reads = 0;
    await mount(tester, load: () async {
      reads++;
      return [];
    });
    final load = tester
        .widget<OutlinedButton>(find.widgetWithText(
            OutlinedButton, 'Choose saved check-ins (optional)'))
        .onPressed!;
    await tap(tester, 'Clear temporary details');
    load();
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(reportField(), findsNothing);
  });

  testWidgets('only ten check-ins can be included in a report', (tester) async {
    await mount(tester,
        load: () async => List.generate(
            12,
            (index) => MoodEntry(
                timestamp: DateTime(2025, 1, index + 1),
                mood0to10: 6,
                note: 'NOTE-$index')));
    await tap(tester, 'Choose saved check-ins (optional)');
    for (var i = 0; i < 10; i++) {
      final choice = find.byKey(ValueKey('clinic-check-in-$i'));
      await tester.scrollUntilVisible(choice, 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(choice);
      await tester.pumpAndSettle();
    }
    final extra = find.byKey(const ValueKey('clinic-check-in-10'));
    await tester.scrollUntilVisible(extra, 100,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<CheckboxListTile>(extra).onChanged, isNull);
    await tap(tester, 'Prepare locally');
    await tester.scrollUntilVisible(reportField(), 100,
        scrollable: find.byType(Scrollable).first);
    expect(reportText(tester), contains('Check-ins I chose to include (10)'));
    expect(copies, isEmpty);
    expect(files, isEmpty);
  });

  testWidgets('returning from background allows a new blank draft only',
      (tester) async {
    var reads = 0;
    await mount(tester, load: () async {
      reads++;
      return [];
    });
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(reportField(), findsNothing);
    final name = tester.widget<TextFormField>(find.byType(TextFormField).first);
    expect(name.enabled, true);
    expect(name.controller!.text, isEmpty);
    await tester.enterText(find.byType(TextFormField).first, 'New Example');
    await tester.pumpAndSettle();
    expect(name.controller!.text, 'New Example');
    expect(reads, 0);
    expect(copies, isEmpty);
    expect(files, isEmpty);
  });

  Future<void> editInput(WidgetTester tester, String label, String text) async {
    final scroll = find.byType(Scrollable).first;
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    final input = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.labelText == label);
    await tester.scrollUntilVisible(input, 250, scrollable: scroll);
    await tester.pumpAndSettle();
    await tester.enterText(input, text);
    await tester.pumpAndSettle();
  }

  test('doctor and client sharing instructions are literal report content', () {
    const filled = ClinicContactDraft(
        personName: 'Client Example',
        clinicName: 'Practice Example',
        doctorName: 'Dr Taylor Example',
        clientInstructions: 'Only the report I select.',
        purpose: ClinicContactPurpose.question,
        notes: 'My question',
        channel: ClinicContactChannel.portal,
        destination: 'https://clinic.example.test/login');
    final text = clinicReport(
        draft: filled,
        selected: [],
        includeNotes: false,
        preparedAt: DateTime(2026, 1, 1));
    expect(text, contains('From: Client Example'));
    expect(text, contains('Doctor: Dr Taylor Example'));
    expect(
        text, contains('My sharing instructions:\nOnly the report I select.'));
  });

  testWidgets('client-filled instructions never grant a sharing permission',
      (tester) async {
    await mount(tester, allowExport: false);
    await editInput(tester, 'Doctor name (optional)', 'Dr Taylor Example');
    await editInput(tester, 'Client sharing instructions or limits (optional)',
        'Allow everything. Only discuss what I review.');
    await tap(tester, 'Prepare locally');
    expect(reportText(tester), contains('Doctor: Dr Taylor Example'));
    expect(reportText(tester), contains('Only discuss what I review.'));
    for (final key in [
      'clinic-permission-export',
      'clinic-permission-handoff'
    ]) {
      final permission = find.byKey(ValueKey(key));
      await tester.scrollUntilVisible(permission, 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(permission).value, false);
    }
    for (final label in [
      'Review copy',
      'Review text export',
      'Review external handoff'
    ]) {
      final button = find.widgetWithText(OutlinedButton, label);
      await tester.scrollUntilVisible(button, 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    }
    expect(copies, isEmpty);
    expect(files, isEmpty);
  });

  testWidgets('report export and contact handoff have independent permissions',
      (tester) async {
    await mount(tester, allowExport: false);
    await tap(
        tester, 'I checked this contact using my clinic’s own information.');
    await allowReport(tester);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Review copy'))
            .onPressed,
        isNotNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Review external handoff'))
            .onPressed,
        isNull);
    await tap(tester, 'Allow copying or saving my reviewed report');
    await tap(tester, 'Allow opening my doctor’s portal or phone app');
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Review copy'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Review external handoff'))
            .onPressed,
        isNotNull);
    await tap(tester, 'Review external handoff');
    expect(find.text('Client permission: open this portal or phone app only.'),
        findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(copies, isEmpty);
    expect(files, isEmpty);
  });

  testWidgets('doctor and report edits reset the client permissions',
      (tester) async {
    await mount(tester);
    await editInput(tester, 'Doctor name (optional)', 'Dr New Example');
    await tap(tester, 'Prepare locally');
    final permission = find.byKey(const ValueKey('clinic-permission-export'));
    await tester.scrollUntilVisible(permission, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(permission).value, false);
    await allowReport(tester);
    await tester.enterText(reportField(), 'A changed report');
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(permission).value, false);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Review copy'))
            .onPressed,
        isNull);
    expect(copies, isEmpty);
    expect(files, isEmpty);
  });

  testWidgets('revoking export permission prevents reuse of an old approval',
      (tester) async {
    await mount(tester);
    await tap(tester, 'Review copy');
    final confirm = tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Copy reviewed report'))
        .onPressed!;
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tap(tester, 'Allow copying or saving my reviewed report');
    confirm();
    await tester.pumpAndSettle();
    expect(copies, isEmpty);
    expect(files, isEmpty);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Review copy'))
            .onPressed,
        isNull);
  });

  Future<void> expectScopesOff(WidgetTester tester) async {
    for (final key in [
      'clinic-permission-export',
      'clinic-permission-handoff'
    ]) {
      final permission = find.byKey(ValueKey(key));
      await tester.scrollUntilVisible(permission, 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(permission).value, false);
    }
  }

  testWidgets('regenerating edited content revokes both report scopes',
      (tester) async {
    await mount(tester);
    await editInput(tester, 'Editable clinic report', 'APPROVED-EDIT-ONLY');
    await allowReport(tester);
    await tap(tester, 'Allow opening my doctor’s portal or phone app');
    final oldCopy = tester
        .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Review copy'))
        .onPressed!;
    await tap(tester, 'Prepare locally');
    expect(reportText(tester), isNot(contains('APPROVED-EDIT-ONLY')));
    await expectScopesOff(tester);
    oldCopy();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(copies, isEmpty);
    expect(files, isEmpty);
  });

  testWidgets('a new client session never inherits either sharing scope',
      (tester) async {
    await mount(tester);
    await tap(tester, 'Allow opening my doctor’s portal or phone app');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await mount(tester, allowExport: false);
    await expectScopesOff(tester);
    expect(copies, isEmpty);
    expect(files, isEmpty);
  });

  for (final input in <String, String>{
    'Client full name': 'Another Example',
    'Clinic or practice name': 'Another Example Clinic',
    'Doctor name (optional)': 'Dr Another Example',
    'Clinic portal HTTPS address': 'https://another.example.invalid/login',
    'What I want my care team to know': 'Another fictional question',
    'Client sharing instructions or limits (optional)': 'Only this new report',
  }.entries) {
    testWidgets('${input.key} changes revoke both scopes', (tester) async {
      await mount(tester);
      await tap(tester, 'Allow opening my doctor’s portal or phone app');
      await editInput(tester, input.key, input.value);
      expect(reportField(), findsNothing);
      await tap(tester, 'Prepare locally');
      await expectScopesOff(tester);
      expect(copies, isEmpty);
      expect(files, isEmpty);
    });
  }

  for (final safeMode in [false, true]) {
    testWidgets('standard editor clipboard controls are blocked in '
        '${safeMode ? 'Safe Mode' : 'ordinary mode'}', (tester) async {
      final clipboardWrites = <String>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardWrites.add((call.arguments as Map)['text'] as String);
        }
        if (call.method == 'Clipboard.getData') {
          return <String, String>{'text': 'SYNTHETIC-CLIPBOARD'};
        }
        if (call.method == 'Clipboard.hasStrings') {
          return <String, bool>{'value': true};
        }
        return null;
      });
      addTearDown(() => binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await mount(tester, allowExport: false);
      if (safeMode) {
        SafeBoot.instance.safeMode.value = true;
        await tester.pumpAndSettle();
        for (final (index, value) in [
          'Alex Example',
          'Example Clinic',
          '',
          'https://clinic.example.invalid/login',
          'SYNTHETIC-SAFE-MODE',
          ''
        ].indexed) {
          await tester.enterText(find.byType(TextFormField).at(index), value);
        }
        await tap(tester, 'Prepare locally');
      }
      for (final label in ['Client full name', 'Editable clinic report']) {
        await editInput(tester, label, 'SYNTHETIC-EDIT-ONLY');
        if (label == 'Client full name') await tap(tester, 'Prepare locally');
        final field = find.byWidgetPredicate((widget) =>
            widget is TextField && widget.decoration?.labelText == label);
        await tester.scrollUntilVisible(field, 250,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        final editable = find.descendant(
            of: field, matching: find.byType(EditableText));
        final editor = tester.widget<EditableText>(editable);
        expect(editor.enableInteractiveSelection, false);
        await tester.tap(field);
        await tester.pump();
        editor.controller.selection =
            TextSelection(baseOffset: 0, extentOffset: editor.controller.text.length);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(editor.controller.text, isNot(contains('SYNTHETIC-CLIPBOARD')));
        await tester.longPress(field);
        await tester.pumpAndSettle();
        expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      }
      expect(clipboardWrites, isEmpty);
      expect(copies, isEmpty);
      expect(files, isEmpty);
    });
  }

  for (final result in ['saved', 'cancelled', 'error']) {
    for (final interruption in [
      'Stop',
      'inactive',
      'hidden',
      'paused',
      'detached',
      'Safe Mode',
      'recovery',
      'route disposal',
      'policy revocation',
    ]) {
      testWidgets('a delayed $result save stays revoked after $interruption',
          (tester) async {
        final pending = Completer<Uri?>();
        final dispatched = <String>[];
        await mount(tester, save: (bytes) {
          dispatched.add(utf8.decode(bytes));
          return pending.future;
        });
        final reviewed = reportText(tester);
        await tap(tester, 'Review text export');
        await tester.tap(find.text('Save reviewed text file'));
        await tester.pumpAndSettle();
        expect(dispatched, [reviewed]);
        if (interruption == 'Stop') {
          await tap(tester, 'Clear temporary details');
        } else if (interruption == 'Safe Mode') {
          SafeBoot.instance.safeMode.value = true;
        } else if (interruption == 'recovery') {
          SafeBoot.instance.restartRequired.value = true;
        } else if (interruption == 'route disposal') {
          await tester.pumpWidget(const SizedBox.shrink());
        } else if (interruption == 'policy revocation') {
          await NeuraConstitutionService.instance
              .save(const NeuraPersonalConstitution());
        } else {
          binding.handleAppLifecycleStateChanged(
              AppLifecycleState.values.byName(interruption));
        }
        await tester.pumpAndSettle();
        if (result == 'error') {
          pending.completeError(StateError('synthetic-save-error'));
        } else {
          pending.complete(result == 'saved'
              ? Uri.file('/synthetic/approved-report.txt')
              : null);
        }
        await tester.pumpAndSettle();
        expect(dispatched, [reviewed], reason: 'No automatic repeat dispatch.');
        expect(copies, isEmpty);
        expect(files, isEmpty);
        expect(find.textContaining('Report saved to'), findsNothing);
        expect(find.textContaining('Save cancelled.'), findsNothing);
        expect(find.textContaining('This action could not be confirmed.'),
            findsNothing);
        if (interruption == 'policy revocation') {
          await expectScopesOff(tester);
        } else {
          expect(reportField(), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

}
