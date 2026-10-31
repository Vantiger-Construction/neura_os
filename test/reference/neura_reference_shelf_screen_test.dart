import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reference/neura_reference_shelf_screen.dart';
import 'package:neuro_companion/reference/neura_reference_shelf.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import '../helpers/data_wipe_fixture.dart';

class _Picker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles(
      {String? dialogTitle,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Function(FilePickerStatus)? onFileLoading,
      bool allowCompression = true,
      int compressionQuality = 30,
      bool allowMultiple = false,
      bool withData = false,
      bool withReadStream = false,
      bool lockParentWindow = false,
      bool readSequential = false}) async {
    final bytes =
        utf8.encode('Private reference heading\nClean the filter monthly.');
    return FilePickerResult([
      PlatformFile(
          name: 'manual.txt',
          size: bytes.length,
          readStream: Stream.value(bytes))
    ]);
  }
}

void main() {
  testWidgets(
      'selected document quotes are visible locally and wiped by background',
      (tester) async {
    FilePicker.platform = _Picker();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester
        .pumpWidget(const MaterialApp(home: NeuraReferenceShelfScreen()));
    await tester.tap(find.text('Select a text document'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'clean filter');
    await tester.tap(find.text('Find source passages'));
    await tester.pumpAndSettle();
    expect(find.text('Clean the filter monthly.'), findsOneWidget);
    expect(find.text('[1] manual.txt, line 2'), findsOneWidget);
    expect(find.text('Source preview — exact passages for your approval'),
        findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Clean the filter monthly.'), findsNothing);
    expect(find.text('Source: manual.txt'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'explicit approval shows separate exact excerpts or uncertainty and Safe Mode clears both',
      (tester) async {
    late DataWipeFixture fixture;
    await tester.runAsync(() async {
      fixture = await DataWipeFixture.create();
    });
    final oldPicker = FilePicker.platform;
    const channel = MethodChannel('neura/engine_synthetic_session');
    var requests = 0;
    var reply = jsonEncode({
      'quotes': [
        {'passage': 1, 'text': 'Clean the filter monthly.'}
      ]
    });
    FilePicker.platform = _Picker();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'beginOllama') return ++requests;
      if (call.method == 'pollOllama') return reply;
      return null;
    });
    addTearDown(() {
      FilePicker.platform = oldPicker;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      SafeBoot.instance.safeMode.value = false;
    });
    await fixture.run(() async {
      await tester
          .pumpWidget(const MaterialApp(home: NeuraReferenceShelfScreen()));
      await tester.tap(find.text('Select a text document'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'clean filter');
      await tester.tap(find.text('Find source passages'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      final approve = find.text('Use these passages for one local answer');
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('Clean the filter monthly.'), findsOneWidget);
      expect(
          find.text(
              'Local reply — quotations checked against the approved passages'),
          findsOneWidget);
      expect(find.textContaining('[1] line 2\nClean the filter monthly.'),
          findsOneWidget);
      expect(
          find.textContaining(
              'cannot establish whether these excerpts fully answer'),
          findsOneWidget);

      reply = 'Clean the filter daily [1].';
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(find.text('Clean the filter daily [1].'), findsNothing);
      expect(find.text(NeuraReferenceGrant.unverifiedReply), findsOneWidget);
      expect(find.text('Clean the filter monthly.'), findsOneWidget);

      SafeBoot.instance.safeMode.value = true;
      await tester.pumpAndSettle();
      expect(find.text(NeuraReferenceGrant.unverifiedReply), findsNothing);
      expect(find.text('Clean the filter monthly.'), findsNothing);
      expect(find.text('Source: manual.txt'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      fixture.expectIsolation();
    });
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
