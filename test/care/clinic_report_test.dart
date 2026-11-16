import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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

  Future<void> mount(WidgetTester tester,
      {Future<List<MoodEntry>> Function()? load,
      Future<void> Function(String)? copy,
      bool cancelSave = false}) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [clinicContactRouteObserver],
      home: ClinicContactScreen(
        loadCheckIns: load ?? () async => [],
        copyReport: copy ?? (text) async => copies.add(text),
        saveReport: (bytes) async {
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
      'https://clinic.example.test/login',
      'My own question'
    ].indexed) {
      await tester.enterText(find.byType(TextFormField).at(index), text);
    }
    await tester.pump();
    await tester.tap(find.text('Prepare locally'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.pump();
    await tester.scrollUntilVisible(find.text(label), 250,
        scrollable: find.byType(Scrollable).first);
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
      await NeuraConstitutionService.instance
          .save(const NeuraPersonalConstitution());
      await tester.tap(
          find.text(save ? 'Save reviewed text file' : 'Copy reviewed report'));
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
}
