import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/preview/neura_demo_app.dart';
import 'package:neuro_companion/preview/neura_demo_session.dart';
import 'package:neuro_companion/preview/neura_lounge_preview_screen.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

const _spots = <String>[
  'sofa_seat',
  'coffee_table',
  'reflection_window',
  'memory_cards',
  'office_handoff',
  'spa_handoff',
];

const _destinations = [
  (
    spot: 'reflection_window',
    action: 'lounge-open-quiet-writing',
    label: 'Quiet writing destination',
  ),
  (
    spot: 'coffee_table',
    action: 'lounge-open-small-step',
    label: 'Small step destination',
  ),
  (
    spot: 'office_handoff',
    action: 'lounge-open-small-step',
    label: 'Small step destination',
  ),
  (
    spot: 'spa_handoff',
    action: 'lounge-open-settle',
    label: 'Settle destination',
  ),
];

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    final scrollable = find.byType(Scrollable).last;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(target, 200,
          scrollable: scrollable, maxScrolls: 30);
    }
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey<String>(key));
  await _reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _expectNoSelection(WidgetTester tester) async {
  final prompt = find.text('Choose a place in the lounge');
  await _reveal(tester, prompt);
  expect(prompt, findsOneWidget);
  expect(find.byKey(const ValueKey('lounge-selection')), findsNothing);
}

Future<String> _selectionText(WidgetTester tester) async {
  final selection = find.byKey(const ValueKey('lounge-selection'));
  await _reveal(tester, selection);
  expect(selection, findsOneWidget);
  return tester
      .widgetList<Text>(
          find.descendant(of: selection, matching: find.byType(Text)))
      .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
      .join('\n');
}

Widget _preview({
  String artworkAsset = 'assets/preview/lounge/lounge.png',
  double textScale = 1,
  ValueChanged<String>? onOpen,
}) {
  Widget destination(String label) {
    onOpen?.call(label);
    return Scaffold(
      appBar: AppBar(title: const Text('Sample destination')),
      body: Center(child: Text(label)),
    );
  }

  return MaterialApp(
    key: UniqueKey(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: NeuraLoungePreviewScreen(
      artworkAsset: artworkAsset,
      quietWritingBuilder: (_) => destination('Quiet writing destination'),
      smallStepBuilder: (_) => destination('Small step destination'),
      settleBuilder: (_) => destination('Settle destination'),
    ),
  );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
  tearDown(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

  testWidgets('demo lounge and its activities never open personal storage',
      (tester) async {
    final session = NeuraDemoSession(now: DateTime.utc(2026, 11, 26));
    addTearDown(session.dispose);
    var privateCalls = 0;
    const secure =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(secure, (_) async {
      privateCalls++;
      throw StateError('Private storage forbidden');
    });
    addTearDown(() =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(secure, null));

    await tester.pumpWidget(NeuraDemoApp(session: session));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'open-lounge-preview');
    expect(find.byType(NeuraLoungePreviewScreen), findsOneWidget);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    for (final item in _destinations) {
      await _tapKey(tester, 'lounge-spot-${item.spot}');
      await _tapKey(tester, item.action);
      expect(find.byType(NeuraLoungePreviewScreen), findsNothing);
      expect(privateCalls, 0);
      expect(() => NeuraPrefsCache.prefs, throwsStateError);
      navigator.pop();
      await tester.pumpAndSettle();
    }
    await _tapKey(tester, 'lounge-spot-memory_cards');
    expect((await _selectionText(tester)).toLowerCase(), contains('sample'));
    expect(privateCalls, 0);
    expect(() => NeuraPrefsCache.prefs, throwsStateError);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('each lounge place presents distinct local content',
      (tester) async {
    await tester.pumpWidget(_preview());
    await tester.pumpAndSettle();
    await _expectNoSelection(tester);
    final contents = <String>{};

    for (final spot in _spots) {
      await _tapKey(tester, 'lounge-spot-$spot');
      expect(find.text('Choose a place in the lounge'), findsNothing);
      final text = await _selectionText(tester);
      expect(text.trim(), isNotEmpty);
      expect(contents.add(text), isTrue,
          reason: '$spot should show its own activity');
      if (spot == 'sofa_seat' || spot == 'memory_cards') {
        expect(text.toLowerCase(), contains('sample'));
      }
      if (spot == 'memory_cards') {
        expect(text.toLowerCase(), contains('reflection'));
      }
    }
  });

  testWidgets('activity actions use only their supplied destination builders',
      (tester) async {
    final opened = <String>{};
    await tester.pumpWidget(_preview(onOpen: (label) => opened.add(label)));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);

    for (final item in _destinations) {
      await _tapKey(tester, 'lounge-spot-${item.spot}');
      expect(opened, isEmpty);
      await _tapKey(tester, item.action);
      expect(find.text(item.label), findsOneWidget);
      expect(opened, <String>{item.label});
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(NeuraLoungePreviewScreen), findsOneWidget);
      opened.clear();
    }
  });

  testWidgets('reset and reopening the lounge discard the local selection',
      (tester) async {
    final session = NeuraDemoSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(NeuraDemoApp(session: session));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'open-lounge-preview');
    await _tapKey(tester, 'lounge-spot-sofa_seat');
    expect(find.text('Choose a place in the lounge'), findsNothing);
    await _tapKey(tester, 'lounge-reset');
    await _expectNoSelection(tester);

    await _tapKey(tester, 'lounge-spot-memory_cards');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tapKey(tester, 'open-lounge-preview');
    await _expectNoSelection(tester);
    expect(() => NeuraPrefsCache.prefs, throwsStateError);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('desktop image markers open the same lounge activities',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_preview());
    await tester.pumpAndSettle();
    for (final spot in _spots) {
      expect(find.byKey(ValueKey('lounge-marker-$spot')), findsOneWidget);
    }

    await _tapKey(tester, 'lounge-marker-coffee_table');
    final markerContent = await _selectionText(tester);
    await _tapKey(tester, 'lounge-reset');
    await _tapKey(tester, 'lounge-spot-coffee_table');
    expect(await _selectionText(tester), markerContent);
  });

  testWidgets('compact and enlarged-text layouts keep every activity usable',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final layout in [
      (size: const Size(360, 800), textScale: 1.0),
      (size: const Size(360, 800), textScale: 2.0),
      (size: const Size(1000, 1000), textScale: 2.0),
    ]) {
      tester.view.physicalSize = layout.size;
      await tester.pumpWidget(_preview(textScale: layout.textScale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final spot in _spots) {
        expect(find.byKey(ValueKey('lounge-marker-$spot')), findsNothing);
        await _tapKey(tester, 'lounge-spot-$spot');
        expect((await _selectionText(tester)).trim(), isNotEmpty);
      }
      await _tapKey(tester, 'lounge-reset');
      await _expectNoSelection(tester);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('unavailable artwork stays readable in a compact enlarged view',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_preview(
        artworkAsset: 'assets/preview/lounge/missing-synthetic-artwork.png',
        textScale: 2));
    await tester.pumpAndSettle();
    final message = find.textContaining('Lounge artwork is unavailable.');
    await _reveal(tester, message);
    expect(message, findsOneWidget);
    final bounds = tester.getRect(message);
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(360));
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.bottom, lessThanOrEqualTo(800));
    final paragraph = tester.renderObject<RenderParagraph>(message);
    final textBoxes = paragraph.getBoxesForSelection(TextSelection(
        baseOffset: 0, extentOffset: paragraph.text.toPlainText().length));
    expect(textBoxes, isNotEmpty);
    for (final box in textBoxes) {
      expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + 0.1),
          reason: 'Every fallback line must fit without being clipped');
    }
    expect(tester.takeException(), isNull);
    await _tapKey(tester, 'lounge-spot-reflection_window');
    await _tapKey(tester, 'lounge-open-quiet-writing');
    expect(find.text('Quiet writing destination'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _tapKey(tester, 'lounge-reset');
    await _expectNoSelection(tester);
  });

  testWidgets('backgrounding clears both shown and pending selections',
      (tester) async {
    await tester.pumpWidget(_preview());
    await tester.pumpAndSettle();
    await _tapKey(tester, 'lounge-spot-memory_cards');
    expect((await _selectionText(tester)).toLowerCase(), contains('sample'));

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await _expectNoSelection(tester);

    final choice = find.byKey(const ValueKey('lounge-spot-sofa_seat'));
    await _reveal(tester, choice);
    await tester.tap(choice);
    // Leave before the frame that would reveal the newly selected content.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await _expectNoSelection(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('lounge-selection')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing before a selection frame suppresses its pending work',
      (tester) async {
    await tester.pumpWidget(_preview());
    await tester.pumpAndSettle();
    final choice = find.byKey(const ValueKey('lounge-spot-reflection_window'));
    await _reveal(tester, choice);
    await tester.tap(choice);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: Text('Preview closed')))));
    await tester.pumpAndSettle();
    expect(find.text('Preview closed'), findsOneWidget);
    expect(find.byType(NeuraLoungePreviewScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape returns from the lounge to the demo home',
      (tester) async {
    final session = NeuraDemoSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(NeuraDemoApp(session: session));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'open-lounge-preview');
    await _tapKey(tester, 'lounge-spot-sofa_seat');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(NeuraLoungePreviewScreen), findsNothing);
    expect(find.byKey(const ValueKey('open-lounge-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
