import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reference/neura_reference_shelf_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

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
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Clean the filter monthly.'), findsNothing);
    expect(find.text('Source: manual.txt'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });
}
