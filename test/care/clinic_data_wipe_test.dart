import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/care/screens/clinic_contact_screen.dart';
import 'package:neuro_companion/care/services/clinic_contact_route_observer.dart';
import 'package:neuro_companion/constitution/neura_constitution_service.dart';
import 'package:neuro_companion/constitution/neura_personal_constitution.dart';
import 'package:neuro_companion/modules/mood/mood_models.dart';
import 'package:neuro_companion/modules/vault/memory_vault_models.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/portable_vault_backup_service.dart';
import 'package:neuro_companion/services/scheduled_backup_settings.dart';
import 'package:neuro_companion/services/vault_item_source.dart';
import 'package:neuro_companion/src/core/data_wipe_service.dart';

import '../helpers/data_wipe_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(find.text(label), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> prepare(WidgetTester tester, ClinicContactScreen screen) async {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await NeuraConstitutionService.instance
        .save(const NeuraPersonalConstitution(allowExternalMessages: true));
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [clinicContactRouteObserver],
      home: screen,
    ));
    await tester.pumpAndSettle();
    for (final (index, value) in [
      'Alex Example',
      'Example Clinic',
      '',
      'https://clinic.example.invalid/login',
      'SYNTHETIC-WIPE-REPORT',
      '',
    ].indexed) {
      await tester.enterText(find.byType(TextFormField).at(index), value);
    }
    await tap(tester, 'Prepare locally');
    await tap(tester, 'Allow copying or saving my reviewed report');
  }

  void expectCleared(WidgetTester tester) {
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.decoration?.labelText == 'Editable clinic report'), findsNothing);
    for (final field in tester.widgetList<TextFormField>(
        find.byType(TextFormField))) {
      expect(field.controller!.text, isEmpty);
    }
    expect(find.textContaining('Report saved to'), findsNothing);
    expect(find.textContaining('Report copied.'), findsNothing);
  }

  for (final operation in ['review', 'history', 'dispatched save']) {
    testWidgets('full wipe revokes a pending clinic $operation',
        (tester) async {
      final fixture = (await tester.runAsync(DataWipeFixture.create))!;
      final history = Completer<List<MoodEntry>>();
      final save = Completer<Uri?>();
      final dispatched = <String>[];
      await prepare(tester, ClinicContactScreen(
        loadCheckIns: () => history.future,
        copyReport: (_) => throw StateError('No clipboard export is approved.'),
        saveReport: (bytes) {
          dispatched.add(utf8.decode(bytes));
          return save.future;
        },
      ));
      VoidCallback? confirm;
      if (operation == 'history') {
        await tap(tester, 'Choose saved check-ins (optional)');
      } else {
        await tap(tester, 'Review text export');
        confirm = tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save reviewed text file'))
            .onPressed!;
        if (operation == 'dispatched save') {
          confirm();
          await tester.pumpAndSettle();
        }
      }
      await tester.runAsync(
          () => fixture.run(NeuraDataWipeService.wipeAllLocalData));
      await tester.pumpAndSettle();
      expectCleared(tester);
      expect(SafeBoot.instance.safeMode.value, true);
      expect(SafeBoot.instance.restartRequired.value, true);
      if (operation == 'review') confirm!();
      if (operation == 'history') {
        history.complete([
          MoodEntry(timestamp: DateTime(2025, 1, 1), mood0to10: 6,
              note: 'LATE-SYNTHETIC-HISTORY'),
        ]);
      }
      if (operation == 'dispatched save') {
        save.complete(Uri.file('/synthetic/already-exported.txt'));
      }
      await tester.pumpAndSettle();
      expect(dispatched, hasLength(operation == 'dispatched save' ? 1 : 0));
      expect(find.byKey(const ValueKey('clinic-check-in-0')), findsNothing);
      expectCleared(tester);
      // Repeated wipe while Safe Mode is already latched must stay closed.
      await tester.runAsync(
          () => fixture.run(NeuraDataWipeService.wipeAllLocalData));
      await tester.pumpAndSettle();
      expectCleared(tester);
      expect(dispatched, hasLength(operation == 'dispatched save' ? 1 : 0));
      fixture.expectIsolation();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an early failed wipe and retry cannot revive a clinic review',
      (tester) async {
    final fixture = (await tester.runAsync(DataWipeFixture.create))!;
    final entered = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    late Future<ScheduledBackupRunResult> backup;
    await tester.runAsync(() => fixture.run(() async {
      await ScheduledBackupSettings.instance
          .enable('synthetic backup passphrase');
      final service = PortableVaultBackupService(
        store: _EmptyVaultSource(),
        backupDirectory: () async {
          entered.complete();
          await release.future;
          return Directory('${fixture.support.path}/synthetic-backup');
        },
      );
      backup = service.runScheduledBackupIfDue(pin: '1234');
      await entered.future;
      PortableVaultBackupService.wipeDrainTimeout =
          const Duration(milliseconds: 20);
    }));
    var saves = 0;
    await prepare(tester, ClinicContactScreen(
      loadCheckIns: () async => [],
      saveReport: (_) async {
        saves++;
        return null;
      },
    ));
    await tap(tester, 'Review text export');
    final confirm = tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save reviewed text file'))
        .onPressed!;
    await tester.runAsync(() => fixture.run(() async {
      await expectLater(NeuraDataWipeService.wipeAllLocalData(),
          throwsA(isA<NeuraDataWipeException>().having(
              (error) => error.failedSteps, 'failed steps',
              contains('backup writer drain'))));
      expect(fixture.preferences.clearCalls, 0);
    }));
    await tester.pumpAndSettle();
    expectCleared(tester);
    confirm();
    await tester.pumpAndSettle();
    expect(saves, 0);
    await tester.runAsync(() => fixture.run(() async {
      release.complete();
      expect((await backup).status, ScheduledBackupStatus.failed);
      await NeuraDataWipeService.wipeAllLocalData();
    }));
    await tester.pumpAndSettle();
    confirm();
    await tester.pumpAndSettle();
    expectCleared(tester);
    expect(saves, 0);
    fixture.expectIsolation();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}

class _EmptyVaultSource implements VaultItemSource {
  @override
  Future<List<VaultItem>> getItems({required String pin}) async => [];

  @override
  Future<int> importItems({required String pin,
      required List<VaultItem> imported, required bool Function() mayWrite}) =>
      throw UnsupportedError('No restore in this synthetic fixture.');
}
