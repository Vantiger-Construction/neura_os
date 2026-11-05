import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reference/neura_reference_shelf_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

import '../helpers/fake_picked_file.dart';

class _Picker extends FilePickerPlatform {
  final requests = <Completer<PlatformFile?>>[];

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    final request = Completer<PlatformFile?>();
    requests.add(request);
    return request.future;
  }
}

PlatformFile _file({Stream<List<int>>? stream}) => FakePickedFile('private.txt',
    stream ?? Stream.value(utf8.encode('Clean the filter monthly.')),
    declaredLength: 25);

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pump();
}

void main() {
  late _Picker picker;
  setUp(() {
    picker = _Picker();
    FilePickerPlatform.instance = picker;
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
  });

  Future<void> mount(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester
        .pumpWidget(const MaterialApp(home: NeuraReferenceShelfScreen()));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      SafeBoot.instance.safeMode.value = false;
      SafeBoot.instance.restartRequired.value = false;
    });
  }

  for (final invalidation in ['clear', 'safe mode', 'recovery']) {
    testWidgets('pending reference selection stays revoked after $invalidation',
        (tester) async {
      await mount(tester);
      await _tap(tester, 'Select a text document');
      if (invalidation == 'clear') {
        await _tap(tester, 'Remove document and clear answer');
      } else {
        final signal = invalidation == 'safe mode'
            ? SafeBoot.instance.safeMode
            : SafeBoot.instance.restartRequired;
        signal.value = true;
        signal.value = false;
      }
      var reads = 0;
      final stream = Stream<List<int>>.multi((controller) {
        reads++;
        controller.add(utf8.encode('Clean the filter monthly.'));
        controller.close();
      });
      picker.requests.single.complete(_file(stream: stream));
      await tester.pumpAndSettle();
      expect(reads, 0);
      expect(find.text('Source: private.txt'), findsNothing);
    });
  }

  for (final beforeResume in [false, true]) {
    testWidgets('reference picker waits for foreground: $beforeResume',
        (tester) async {
      await mount(tester);
      await _tap(tester, 'Select a text document');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      var reads = 0;
      final result = _file(stream: Stream<List<int>>.multi((controller) {
        reads++;
        controller.add(utf8.encode('Clean the filter monthly.'));
        controller.close();
      }));
      if (beforeResume) {
        picker.requests.single.complete(result);
        await tester.pump();
        expect(reads, 0);
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      if (!beforeResume) picker.requests.single.complete(result);
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(find.text('Source: private.txt'), findsOneWidget);
    });
  }

  testWidgets('only one native reference picker may be pending',
      (tester) async {
    await mount(tester);
    await _tap(tester, 'Select a text document');
    await _tap(tester, 'Select a text document');
    expect(picker.requests, hasLength(1));
    picker.requests.single.complete(null);
    await tester.pumpAndSettle();
  });

  for (final interruption in ['clear', 'safe mode', 'dispose']) {
    testWidgets('selection waiting for foreground is revoked by $interruption',
        (tester) async {
      await mount(tester);
      await _tap(tester, 'Select a text document');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      picker.requests.single.complete(_file());
      await tester.pump();
      if (interruption == 'dispose') {
        await tester.pumpWidget(const SizedBox());
      } else if (interruption == 'safe mode') {
        SafeBoot.instance.safeMode.value = true;
        SafeBoot.instance.safeMode.value = false;
      } else {
        await _tap(tester, 'Remove document and clear answer');
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Source: private.txt'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final interruption in ['clear', 'background', 'safe mode']) {
    testWidgets('partial reference read cannot restore after $interruption',
        (tester) async {
      await mount(tester);
      final stream = StreamController<List<int>>();
      await _tap(tester, 'Select a text document');
      picker.requests.single.complete(_file(stream: stream.stream));
      await tester.pump();
      stream.add(utf8.encode('Clean the '));
      await tester.pump();
      if (interruption == 'clear') {
        await _tap(tester, 'Remove document and clear answer');
      } else if (interruption == 'background') {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      } else {
        SafeBoot.instance.safeMode.value = true;
        SafeBoot.instance.safeMode.value = false;
      }
      stream.add(utf8.encode('filter monthly.'));
      unawaited(stream.close());
      await tester.pumpAndSettle();
      expect(find.text('Source: private.txt'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stale picker failure is silent and a new request can succeed',
      (tester) async {
    await mount(tester);
    await _tap(tester, 'Select a text document');
    await _tap(tester, 'Remove document and clear answer');
    picker.requests.single
        .completeError(StateError('Synthetic picker failure'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not read that file.'), findsNothing);
    await _tap(tester, 'Select a text document');
    picker.requests.last.complete(_file());
    await tester.pumpAndSettle();
    expect(find.text('Source: private.txt'), findsOneWidget);
  });
}
