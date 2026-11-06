import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/vault/backup_restore_screen.dart';
import 'package:neuro_companion/modules/vault/memory_vault_models.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/portable_backup_codec.dart';
import 'package:neuro_companion/services/portable_vault_backup_service.dart';
import 'package:neuro_companion/services/vault_item_source.dart';
import '../../helpers/fake_picked_file.dart';

Map<String, dynamic> payload() => {
      'type': 'neura-memory-vault',
      'version': 1,
      'items': [
        for (final id in ['a', 'b'])
          VaultItem(
              id: id,
              createdAt: DateTime.utc(2026, 1, 1),
              title: 'Synthetic entry $id',
              body: 'Private body $id',
              tags: const []).toJson()
      ],
    };

// UI fixtures only. Service/codec tests exercise real encrypted envelopes.
class _Codec extends PortableBackupCodec {
  Completer<Map<String, dynamic>>? pending;
  String expectedPassphrase = 'synthetic passphrase';
  @override
  Future<Map<String, dynamic>> decrypt(
      {required String envelope, required String passphrase}) async {
    if (envelope != 'synthetic-ciphertext' ||
        passphrase != expectedPassphrase) {
      throw const FormatException('Synthetic failure');
    }
    return pending == null ? payload() : await pending!.future;
  }
}

class _Store implements VaultItemSource {
  final writes = <List<VaultItem>>[];
  final commits = <List<VaultItem>>[];
  Completer<int>? pending;
  @override
  Future<List<VaultItem>> getItems({required String pin}) async =>
      throw StateError('Verification must not read the vault.');
  @override
  Future<int> importItems(
      {required String pin,
      required List<VaultItem> imported,
      bool Function()? mayWrite}) async {
    writes.add(imported);
    final count = pending == null ? imported.length : await pending!.future;
    if (mayWrite != null && !mayWrite()) throw StateError('Restore revoked.');
    commits.add(imported);
    return count;
  }
}

class _Picker extends FilePickerPlatform {
  final requests = <Completer<PlatformFile?>>[];
  @override
  Future<PlatformFile?> pickFile(
      {String? dialogTitle,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Function(FilePickerStatus)? onFileLoading,
      int compressionQuality = 0,
      AndroidOptions androidOptions = const AndroidOptions(),
      DarwinOptions darwinOptions = const DarwinOptions(),
      WindowsOptions windowsOptions = const WindowsOptions(),
      LinuxOptions linuxOptions = const LinuxOptions(),
      WebOptions webOptions = const WebOptions()}) {
    final request = Completer<PlatformFile?>();
    requests.add(request);
    return request.future;
  }
}

Future<void> tap(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 150,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  late _Picker picker;
  late _Codec codec;
  late _Store store;
  late FilePickerPlatform oldPicker;
  setUp(() {
    oldPicker = FilePickerPlatform.instance;
    picker = _Picker();
    FilePickerPlatform.instance = picker;
    codec = _Codec();
    store = _Store();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
  });
  tearDown(() => FilePickerPlatform.instance = oldPicker);

  Future<void> mount(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(
        home: BackupRestoreScreen(
            service: PortableVaultBackupService(codec: codec, store: store),
            sessionPin: () => '1234')));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      SafeBoot.instance.safeMode.value = false;
      SafeBoot.instance.restartRequired.value = false;
    });
  }

  Future<void> select(WidgetTester tester) async {
    await tap(tester, 'Choose encrypted backup');
    picker.requests.last.complete(FakePickedFile.fromBytes(
        'synthetic.neurabackup', utf8.encode('synthetic-ciphertext')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'synthetic passphrase');
  }

  Future<void> verify(WidgetTester tester) async {
    await select(tester);
    await tap(tester, 'Verify without importing');
    await tester.pumpAndSettle();
  }

  testWidgets(
      'verify writes nothing; only a selected confirmed entry is restored',
      (tester) async {
    await mount(tester);
    await verify(tester);
    expect(store.writes, isEmpty);
    expect(find.text('Verified 2 entries. Your vault has not changed.'),
        findsOneWidget);
    expect(find.text('Private body a'), findsNothing);
    expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((tile) => tile.value == false),
        true);
    await tap(tester, 'Synthetic entry b');
    await tap(tester, 'Review selected restore');
    await tester.pumpAndSettle();
    expect(store.writes, isEmpty);
    await tester.tap(find.text('Restore selected'));
    await tester.pumpAndSettle();
    expect(store.writes.single.map((item) => item.id), ['b']);
    expect(find.text('Restored 1 entry. Existing entries were preserved.'),
        findsOneWidget);
  });

  testWidgets('existing long backup passphrases are never truncated',
      (tester) async {
    await mount(tester);
    await select(tester);
    codec.expectedPassphrase = 'synthetic-long-passphrase-' * 20;
    await tester.enterText(find.byType(TextField), codec.expectedPassphrase);
    await tap(tester, 'Verify without importing');
    await tester.pumpAndSettle();
    expect(find.text('Verified 2 entries. Your vault has not changed.'),
        findsOneWidget);
    expect(store.writes, isEmpty);
  });

  testWidgets('native picker waits for resume before reading ciphertext',
      (tester) async {
    await mount(tester);
    await tap(tester, 'Choose encrypted backup');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    var reads = 0;
    picker.requests.single.complete(
        FakePickedFile('synthetic.neurabackup', Stream.multi((controller) {
      reads++;
      controller.add(utf8.encode('synthetic-ciphertext'));
      controller.close();
    })));
    await tester.pump();
    expect(reads, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.byType(TextField), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
  });

  for (final reason in ['background', 'safe mode', 'clear']) {
    testWidgets('late decryption cannot restore a review after $reason',
        (tester) async {
      await mount(tester);
      await select(tester);
      codec.pending = Completer<Map<String, dynamic>>();
      await tap(tester, 'Verify without importing');
      if (reason == 'background') {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      } else if (reason == 'safe mode') {
        SafeBoot.instance.safeMode.value = true;
        SafeBoot.instance.safeMode.value = false;
      } else {
        await tap(tester, 'Clear backup review');
      }
      codec.pending!.complete(payload());
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('Synthetic entry a'), findsNothing);
      expect(store.writes, isEmpty);
    });
  }

  testWidgets('background revokes a pending restore confirmation',
      (tester) async {
    await mount(tester);
    await verify(tester);
    await tap(tester, 'Synthetic entry b');
    await tap(tester, 'Review selected restore');
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(find.text('Restore selected'));
    await tester.pumpAndSettle();
    expect(store.writes, isEmpty);
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets(
      'clearing a review cannot admit a second operation during a vault write',
      (tester) async {
    await mount(tester);
    await verify(tester);
    await tap(tester, 'Synthetic entry a');
    await tap(tester, 'Review selected restore');
    await tester.pumpAndSettle();
    store.pending = Completer<int>();
    await tester.tap(find.text('Restore selected'));
    await tester.pump(const Duration(milliseconds: 400));
    await tap(tester, 'Clear backup review');
    await tap(tester, 'Choose encrypted backup');
    expect(picker.requests, hasLength(1));
    expect(store.writes, hasLength(1));
    store.pending!.complete(1);
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final reason in ['background', 'safe mode', 'clear', 'disposal']) {
    testWidgets('pending restore cannot commit after $reason', (tester) async {
      await mount(tester);
      await verify(tester);
      await tap(tester, 'Synthetic entry a');
      await tap(tester, 'Review selected restore');
      await tester.pumpAndSettle();
      store.pending = Completer<int>();
      await tester.tap(find.text('Restore selected'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.writes, hasLength(1));
      if (reason == 'background') {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      } else if (reason == 'safe mode') {
        SafeBoot.instance.safeMode.value = true;
        SafeBoot.instance.safeMode.value = false;
      } else if (reason == 'clear') {
        await tap(tester, 'Clear backup review');
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      store.pending!.complete(1);
      await tester.pumpAndSettle();
      expect(store.commits, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
