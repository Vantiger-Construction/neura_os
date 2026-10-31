import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/planning/neura_daily_plan.dart';
import 'package:neuro_companion/planning/neura_task_transfer.dart';
import 'package:neuro_companion/planning/neura_task_transfer_screen.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';

class _Picker extends FilePicker {
  final requests = <Completer<FilePickerResult?>>[];

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) {
    expect(type, FileType.custom);
    expect(allowedExtensions, ['neuratask']);
    expect(allowMultiple, false);
    expect(withData, false);
    expect(withReadStream, true);
    final request = Completer<FilePickerResult?>();
    requests.add(request);
    return request.future;
  }
}

FilePickerResult _file(String packet, {int? size, Stream<List<int>>? stream}) =>
    FilePickerResult([
      PlatformFile(
          name: 'synthetic.neuratask',
          size: size ?? utf8.encode(packet).length,
          readStream: stream ?? Stream.value(utf8.encode(packet)))
    ]);

TextEditingController _packet(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!;
TextEditingController _key(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).last).controller!;

Future<void> _tap(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty &&
      find.byType(Scrollable).evaluate().isNotEmpty) {
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
  }
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pump();
}

Future<void> _background(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

Future<void> _resume(WidgetTester tester) async {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

void main() {
  late _Picker picker;
  late FilePicker originalPicker;
  late NeuraTaskPacket sealed;

  setUpAll(() async {
    // Flutter's Linux test runner does not register the native picker plugin.
    FilePicker.platform = _Picker();
    sealed = await NeuraTaskTransfer.seal(NeuraTaskSnapshot(
        goal: 'Synthetic transferred goal',
        steps: ['First synthetic step', 'Second synthetic step'],
        completed: {0}));
  });

  setUp(() {
    originalPicker = FilePicker.platform;
    picker = _Picker();
    FilePicker.platform = picker;
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
  });

  tearDown(() {
    FilePicker.platform = originalPicker;
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
  });

  Future<void> mount(WidgetTester tester) async {
    await _resume(tester);
    await tester.pumpWidget(const MaterialApp(home: NeuraTaskTransferScreen()));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await _resume(tester);
    });
  }

  for (final resultBeforeResume in [false, true]) {
    testWidgets(
        'picker lifecycle round trip accepts ciphertext with result before resume: $resultBeforeResume',
        (tester) async {
      await mount(tester);
      await tester.enterText(find.byType(TextField).first, 'old packet');
      await tester.enterText(find.byType(TextField).last, 'old secret');
      await _tap(tester, 'Load encrypted packet file');
      await _background(tester);
      expect(_packet(tester).text, isEmpty);
      expect(_key(tester).text, isEmpty);
      if (resultBeforeResume) {
        picker.requests.single.complete(_file(sealed.packet));
        await tester.pump();
        expect(_packet(tester).text, isEmpty);
        await _resume(tester);
      } else {
        await _resume(tester);
        picker.requests.single.complete(_file(sealed.packet));
      }
      await tester.pumpAndSettle();
      expect(_packet(tester).text, sealed.packet);
      expect(_key(tester).text, isEmpty);
      expect(find.text('Synthetic transferred goal'), findsNothing);
      expect(find.text('Bring this preview into my planner'), findsNothing);
    });
  }

  for (final invalidation in ['clear', 'safe mode', 'recovery', 'edit']) {
    testWidgets('pending picker stays invalid after $invalidation',
        (tester) async {
      await mount(tester);
      await _tap(tester, 'Load encrypted packet file');
      if (invalidation == 'clear') {
        await _tap(tester, 'Clear transfer');
      } else if (invalidation == 'safe mode') {
        SafeBoot.instance.safeMode.value = true;
        SafeBoot.instance.safeMode.value = false;
      } else if (invalidation == 'recovery') {
        SafeBoot.instance.restartRequired.value = true;
        SafeBoot.instance.restartRequired.value = false;
      } else {
        await tester.enterText(
            find.byType(TextField).first, 'new manual packet');
      }
      picker.requests.single.complete(_file(sealed.packet));
      await tester.pumpAndSettle();
      expect(_packet(tester).text,
          invalidation == 'edit' ? 'new manual packet' : isEmpty);
      expect(_key(tester).text, isEmpty);
      expect(find.text('Bring this preview into my planner'), findsNothing);
    });
  }

  testWidgets('only one picker request may be pending', (tester) async {
    await mount(tester);
    await _tap(tester, 'Load encrypted packet file');
    await _tap(tester, 'Load encrypted packet file');
    expect(picker.requests, hasLength(1));
    picker.requests.first.complete(null);
    await tester.pumpAndSettle();
  });

  for (final background in [false, true]) {
    testWidgets(
        'picker cancellation clears fields and allows retry: $background',
        (tester) async {
      await mount(tester);
      await tester.enterText(find.byType(TextField).first, sealed.packet);
      await tester.enterText(find.byType(TextField).last, sealed.key);
      await _tap(tester, 'Load encrypted packet file');
      // Clear at launch, even when a desktop picker does not lose focus.
      expect(_packet(tester).text, isEmpty);
      expect(_key(tester).text, isEmpty);
      if (background) await _background(tester);
      picker.requests.first.complete(null);
      await tester.pump();
      await _resume(tester);
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Could not read the encrypted packet.'), findsNothing);
      await _tap(tester, 'Load encrypted packet file');
      picker.requests.last.complete(_file(sealed.packet));
      await tester.pumpAndSettle();
      expect(_packet(tester).text, sealed.packet);
      expect(_key(tester).text, isEmpty);
    });
  }

  for (final interruption in ['background', 'clear', 'safe mode', 'recovery']) {
    testWidgets('streamed result cannot restore data after $interruption',
        (tester) async {
      await mount(tester);
      final stream = StreamController<List<int>>();
      await _tap(tester, 'Load encrypted packet file');
      picker.requests.single
          .complete(_file(sealed.packet, stream: stream.stream));
      await tester.pump();
      stream.add(utf8.encode(sealed.packet.substring(0, 10)));
      await tester.pump();
      if (interruption == 'background') {
        await _background(tester);
        await _resume(tester);
      } else if (interruption == 'clear') {
        await _tap(tester, 'Clear transfer');
      } else if (interruption == 'safe mode') {
        SafeBoot.instance.safeMode.value = true;
        SafeBoot.instance.safeMode.value = false;
      } else {
        SafeBoot.instance.restartRequired.value = true;
        SafeBoot.instance.restartRequired.value = false;
      }
      stream.add(utf8.encode(sealed.packet.substring(10)));
      unawaited(stream.close());
      await tester.runAsync(() async {});
      await tester.pumpAndSettle();
      expect(_packet(tester).text, isEmpty);
      expect(_key(tester).text, isEmpty);
      expect(find.text('Bring this preview into my planner'), findsNothing);
      expect(find.text('Could not read the encrypted packet.'), findsNothing);
    });
  }

  for (final interruption in ['clear', 'safe mode', 'recovery', 'dispose']) {
    testWidgets('selection waiting for resume is revoked by $interruption',
        (tester) async {
      await mount(tester);
      var listened = false;
      final stream = Stream<List<int>>.multi((controller) {
        listened = true;
        controller.add(utf8.encode(sealed.packet));
        controller.close();
      });
      await _tap(tester, 'Load encrypted packet file');
      await _background(tester);
      picker.requests.single.complete(_file(sealed.packet, stream: stream));
      await tester.pump();
      expect(listened, false);
      if (interruption == 'clear') {
        // Invoke the user's clear action while frames are suspended.
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Clear transfer'))
            .onPressed!();
      } else if (interruption == 'safe mode') {
        SafeBoot.instance.safeMode.value = true;
        SafeBoot.instance.safeMode.value = false;
      } else if (interruption == 'recovery') {
        SafeBoot.instance.restartRequired.value = true;
        SafeBoot.instance.restartRequired.value = false;
      } else {
        await tester.pumpWidget(const SizedBox());
        tester.binding.scheduleForcedFrame();
        await tester.pump();
      }
      await _resume(tester);
      await tester.pumpAndSettle();
      expect(listened, false);
      expect(tester.takeException(), isNull);
      if (interruption != 'dispose') {
        expect(_packet(tester).text, isEmpty);
        expect(_key(tester).text, isEmpty);
        expect(find.byType(LinearProgressIndicator), findsNothing);
      }
    });
  }

  testWidgets('a picker result after screen disposal is ignored',
      (tester) async {
    await mount(tester);
    await _tap(tester, 'Load encrypted packet file');
    await tester.pumpWidget(const SizedBox());
    picker.requests.single.complete(_file(sealed.packet));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second background trip revokes a delayed native picker result',
      (tester) async {
    await mount(tester);
    await _tap(tester, 'Load encrypted packet file');
    await _background(tester);
    await _resume(tester);
    // Native file caching can delay completion beyond the first resume. A new
    // interruption is no longer part of the picker round trip.
    await _background(tester);
    await _resume(tester);
    picker.requests.single.complete(_file(sealed.packet));
    await tester.pumpAndSettle();
    expect(_packet(tester).text, isEmpty);
    expect(_key(tester).text, isEmpty);
  });

  testWidgets('a picker result cannot populate a covered route',
      (tester) async {
    await mount(tester);
    await _tap(tester, 'Load encrypted packet file');
    final controller = _packet(tester);
    final context = tester.element(find.byType(NeuraTaskTransferScreen));
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Another route')))));
    await tester.pumpAndSettle();
    picker.requests.single.complete(_file(sealed.packet));
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
  });

  for (final unsafe in ['safe mode', 'recovery', 'inactive']) {
    testWidgets('picker cannot start during $unsafe', (tester) async {
      await mount(tester);
      if (unsafe == 'safe mode') {
        SafeBoot.instance.safeMode.value = true;
      } else if (unsafe == 'recovery') {
        SafeBoot.instance.restartRequired.value = true;
      } else {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      }
      await tester.pump();
      await _tap(tester, 'Load encrypted packet file');
      expect(picker.requests, isEmpty);
      await _resume(tester);
    });
  }

  for (final failure in ['picker', 'stream']) {
    testWidgets('stale $failure errors cannot replace the clear status',
        (tester) async {
      await mount(tester);
      final stream = StreamController<List<int>>();
      await _tap(tester, 'Load encrypted packet file');
      if (failure == 'stream') {
        picker.requests.single
            .complete(_file(sealed.packet, stream: stream.stream));
        await tester.pump();
      }
      await _tap(tester, 'Clear transfer');
      if (failure == 'picker') {
        picker.requests.single
            .completeError(StateError('Synthetic picker failure'));
      } else {
        stream.addError(StateError('Synthetic read failure'));
        unawaited(stream.close());
      }
      await tester.pumpAndSettle();
      expect(find.text('Could not read the encrypted packet.'), findsNothing);
      expect(find.text('Transfer cleared. Return to your plan to start again.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final invalidFile in [
    'reported oversize',
    'streamed oversize',
    'invalid UTF-8',
    'missing stream',
    'multiple files'
  ]) {
    testWidgets('rejects $invalidFile without restoring a key', (tester) async {
      await mount(tester);
      await _tap(tester, 'Load encrypted packet file');
      final FilePickerResult result;
      switch (invalidFile) {
        case 'reported oversize':
          result = _file(sealed.packet,
              size: NeuraTaskTransfer.maxPacketCharacters + 1);
        case 'streamed oversize':
          result = _file('x',
              stream: Stream.fromIterable([
                List.filled(NeuraTaskTransfer.maxPacketCharacters, 65),
                [65]
              ]));
        case 'invalid UTF-8':
          result = _file('x', stream: Stream.value([0xff]));
        case 'missing stream':
          result =
              FilePickerResult([PlatformFile(name: 'task.neuratask', size: 1)]);
        default:
          result = FilePickerResult(
              [..._file(sealed.packet).files, ..._file(sealed.packet).files]);
      }
      picker.requests.single.complete(result);
      await tester.runAsync(() async {});
      await tester.pumpAndSettle();
      expect(_packet(tester).text, isEmpty);
      expect(_key(tester).text, isEmpty);
      expect(find.text('Could not read the encrypted packet.'), findsOneWidget);
      expect(find.text('Bring this preview into my planner'), findsNothing);
    });
  }

  Future<void> decrypt(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Decrypt and preview'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Decrypt and preview'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  for (final invalid in ['malformed key', 'wrong key', 'expired packet']) {
    testWidgets('picked $invalid cannot become a task preview', (tester) async {
      await mount(tester);
      var packet = sealed.packet;
      var key = invalid == 'malformed key'
          ? 'invalid'
          : base64UrlEncode(List.filled(32, 0));
      if (invalid == 'expired packet') {
        final expired = await tester.runAsync(() => NeuraTaskTransfer.seal(
            NeuraTaskSnapshot(
                goal: 'Expired goal', steps: ['Expired step'], completed: {}),
            now: DateTime.now().subtract(const Duration(minutes: 31))));
        packet = expired!.packet;
        key = expired.key;
      }
      await _tap(tester, 'Load encrypted packet file');
      picker.requests.single.complete(_file(packet));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, key);
      await decrypt(tester);
      expect(find.text('Bring this preview into my planner'), findsNothing);
      expect(
          find.text(
              'Could not open the packet. Check the key, expiry and device clocks.'),
          findsOneWidget);
    });
  }

  testWidgets(
      'picker import requires decryption, preview and fresh plan approval',
      (tester) async {
    NeuraTaskSnapshot? received;
    await _resume(tester);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
              onPressed: () async {
                received = await Navigator.of(context).push<NeuraTaskSnapshot>(
                    MaterialPageRoute(
                        builder: (_) => const NeuraTaskTransferScreen()));
              },
              child: const Text('Receive')));
    })));
    await _tap(tester, 'Receive');
    await tester.pumpAndSettle();
    await _tap(tester, 'Load encrypted packet file');
    picker.requests.single.complete(_file(sealed.packet));
    await tester.pumpAndSettle();
    expect(_packet(tester).text, sealed.packet);
    expect(received, isNull);
    expect(find.text('Bring this preview into my planner'), findsNothing);
    await tester.enterText(find.byType(TextField).last, sealed.key);
    await decrypt(tester);
    expect(
        find.text(
            'Could not open the packet. Check the key, expiry and device clocks.'),
        findsNothing);
    expect(_key(tester).text, sealed.key);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(received, isNull);
    await _tap(tester, 'Bring this preview into my planner');
    await tester.pumpAndSettle();
    expect(received!.goal, 'Synthetic transferred goal');
    final plan = NeuraDailyPlan();
    addTearDown(plan.dispose);
    plan.previewTransferred(
        received!.goal, received!.steps, received!.completed);
    expect(plan.approved, false);
    expect(plan.completedCount, 1);
    expect(() => plan.complete(1, true), throwsStateError);
    plan.approve();
    plan.complete(1, true);
    expect(plan.completedCount, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
