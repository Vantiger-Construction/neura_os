import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/neura_avatar_runtime_bridge.dart';
import 'package:neuro_companion/her_suite/her_shelf_source.dart';
import 'package:neuro_companion/her_suite/her_suite_screens.dart';
import 'package:neuro_companion/her_suite/her_suite_stage_controller.dart';
import 'package:neuro_companion/intelligence/intelligence_preferences.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/teaching/neura_teaching_preferences.dart';

class _Host implements HerSuiteHost {
  _Host(this.room);
  @override
  NeuraRoom room;
  final visits = <String>[];
  @override
  Future<void> setRoom(NeuraRoom next) async {
    room = next;
    visits.add(next.id);
  }
}

class _Shelf extends ChangeNotifier implements HerShelfSource {
  _Shelf(this.summary);
  HerShelfSummary summary;
  int loads = 0;
  @override
  void ensureLoaded() => loads++;
  @override
  HerShelfSummary read() => summary;
  void set(HerShelfSummary next) {
    summary = next;
    notifyListeners();
  }
}

const _taught = HerShelfSummary(
  safeMode: false,
  teachingAvailable: true,
  answerDetail: NeuraAnswerDetail.brief,
  planSize: NeuraPlanSize.three,
  planIsTemporary: true,
  suggestions: NeuraProactivityLevel.subtle,
  quietHoursEnabled: true,
  quietHoursStart: 22,
  quietHoursEnd: 7,
);

const _safe = HerShelfSummary(
  safeMode: true,
  teachingAvailable: false,
  suggestions: NeuraProactivityLevel.off,
  quietHoursEnabled: false,
  quietHoursStart: 22,
  quietHoursEnd: 7,
);

const _unreadable = HerShelfSummary(
  safeMode: false,
  teachingAvailable: true,
  teachingUnreadable: true,
  suggestions: NeuraProactivityLevel.balanced,
  quietHoursEnabled: false,
  quietHoursStart: 22,
  quietHoursEnd: 7,
);

Widget _page(String name) {
  return Scaffold(appBar: AppBar(), body: Text('opened $name'));
}

const _destinations = HerSuiteDestinations(
  chat: _chat,
  teach: _teach,
  memory: _memory,
  suggestions: _suggestions,
);
Widget _chat(BuildContext _) => _page('chat');
Widget _teach(BuildContext _) => _page('teach');
Widget _memory(BuildContext _) => _page('memory');
Widget _suggestions(BuildContext _) => _page('suggestions');

Widget _stage(BuildContext _, NeuraStagePresentation stage) {
  final camera = stage.camera.name;
  return Text('stage ${stage.lighting.name} $camera ${stage.activity.name}');
}

void main() {
  group('HerSuiteStageController', () {
    late List<NeuraStagePresentation> published;
    late ValueNotifier<bool> safeMode;
    late HerSuiteStageController controller;

    setUp(() {
      published = [];
      safeMode = ValueNotifier(false);
      controller = HerSuiteStageController(
        publish: published.add,
        safeMode: safeMode,
      );
    });

    tearDown(() {
      controller.dispose();
      safeMode.dispose();
    });

    test('publishes each display-only choice to the presence bridge', () {
      controller.setLighting(NeuraStageLighting.aurora);
      controller.setCamera(NeuraStageCamera.face);
      expect(controller.rest(), isTrue);
      expect(published.last.lighting, NeuraStageLighting.aurora);
      expect(published.last.camera, NeuraStageCamera.face);
      expect(published.last.activity, NeuraCompanionActivity.resting);
      controller.wake();
      expect(published.last.activity, NeuraCompanionActivity.present);
    });

    test('Safe Mode refuses rest and ends a rest in progress', () {
      expect(controller.rest(), isTrue);
      safeMode.value = true;
      expect(controller.resting, isFalse);
      expect(published.last.activity, NeuraCompanionActivity.present);
      final count = published.length;
      expect(controller.rest(), isFalse);
      expect(published.length, count);
    });

    test('closing restores the default stage and ignores later choices', () {
      controller.setLighting(NeuraStageLighting.dusk);
      controller.close();
      expect(published.last, NeuraStagePresentation.defaults);
      final count = published.length;
      controller.setCamera(NeuraStageCamera.wide);
      expect(published.length, count);
    });

    test('drives the real bridge, which keeps resting to Her Suite', () {
      final bridge = NeuraAvatarRuntimeBridge.instance;
      addTearDown(bridge.reset);
      final live = HerSuiteStageController(safeMode: safeMode);
      addTearDown(live.dispose);
      live.rest();
      expect(bridge.stage.activity, NeuraCompanionActivity.resting);
      live.close();
      expect(bridge.stage, NeuraStagePresentation.defaults);
    });
  });

  group('Her Suite screens', () {
    late _Host host;
    late _Shelf shelf;
    late List<NeuraStagePresentation> published;
    late ValueNotifier<bool> safeMode;
    late HerSuiteStageController controller;

    setUp(() {
      host = _Host(NeuraRoom.penthouse);
      shelf = _Shelf(_taught);
      published = [];
      safeMode = ValueNotifier(false);
      controller = HerSuiteStageController(
        publish: published.add,
        safeMode: safeMode,
      );
    });

    tearDown(() {
      controller.dispose();
      shelf.dispose();
      safeMode.dispose();
    });

    Future<void> openSuite(WidgetTester tester) async {
      Widget suite(BuildContext _) {
        return HerSuiteScreen(
          host: host,
          controller: controller,
          shelf: shelf,
          destinations: _destinations,
          stageBuilder: _stage,
        );
      }

      Widget visit(BuildContext context) {
        return TextButton(
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute<void>(builder: suite));
          },
          child: const Text('visit'),
        );
      }

      await tester.pumpWidget(MaterialApp(home: Builder(builder: visit)));
      await tester.tap(find.text('visit'));
      await tester.pumpAndSettle();
    }

    Future<void> back(WidgetTester tester) async {
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
    }

    testWidgets('visiting moves to Her Suite and leaving goes back',
        (tester) async {
      await openSuite(tester);
      expect(host.room, NeuraRoom.herSuite);
      expect(find.text('Her Suite'), findsOneWidget);
      final cue = find.text("Neura's own room. You're a guest here.");
      expect(cue, findsOneWidget);
      await back(tester);
      expect(host.visits, ['her_suite', 'penthouse']);
      expect(published.last, NeuraStagePresentation.defaults);
    });

    testWidgets('light and view choices reach the stage and the bridge',
        (tester) async {
      await openSuite(tester);
      await tester.tap(find.byKey(const ValueKey('her-suite-light-aurora')));
      await tester.tap(find.byKey(const ValueKey('her-suite-camera-wide')));
      await tester.pumpAndSettle();
      expect(find.text('stage aurora wide present'), findsOneWidget);
      expect(published.last.lighting, NeuraStageLighting.aurora);
      expect(published.last.camera, NeuraStageCamera.wide);
    });

    testWidgets('sitting together comes face to face, then restores the view',
        (tester) async {
      await openSuite(tester);
      await tester.tap(find.byKey(const ValueKey('her-suite-camera-wide')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('her-suite-sit')));
      await tester.pumpAndSettle();
      expect(controller.stage.camera, NeuraStageCamera.face);
      await tester.tap(find.byKey(const ValueKey('her-suite-talk')));
      await tester.pumpAndSettle();
      expect(find.text('opened chat'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await back(tester);
      expect(controller.stage.camera, NeuraStageCamera.wide);
    });

    testWidgets('her shelf shows taught settings as labels and links out',
        (tester) async {
      await openSuite(tester);
      await tester.tap(find.byKey(const ValueKey('her-suite-shelf')));
      await tester.pumpAndSettle();
      expect(shelf.loads, 1);
      expect(find.text('Brief'), findsOneWidget);
      expect(find.text('Three steps (today only)'), findsOneWidget);
      expect(find.text('Subtle'), findsOneWidget);
      expect(find.text('22:00 to 07:00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('her-shelf-memories')));
      await tester.pumpAndSettle();
      expect(find.text('opened memory'), findsOneWidget);
    });

    testWidgets('her shelf closes in Safe Mode', (tester) async {
      await openSuite(tester);
      await tester.tap(find.byKey(const ValueKey('her-suite-shelf')));
      await tester.pumpAndSettle();
      shelf.set(_safe);
      await tester.pump();
      expect(find.byKey(const ValueKey('her-shelf-closed')), findsOneWidget);
      expect(find.byKey(const ValueKey('her-shelf-memories')), findsNothing);
    });

    testWidgets('resting settles her and waking on leave stands her up',
        (tester) async {
      await openSuite(tester);
      await tester.tap(find.byKey(const ValueKey('her-suite-rest')));
      await tester.pumpAndSettle();
      expect(controller.resting, isTrue);
      expect(find.text('stage standard follow resting'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('her-suite-wake')));
      await tester.pumpAndSettle();
      expect(controller.resting, isFalse);
      expect(find.text('Her Suite'), findsOneWidget);
    });

    testWidgets('a room picked elsewhere during the visit is kept',
        (tester) async {
      await openSuite(tester);
      await host.setRoom(NeuraRoom.dreamAtrium);
      await back(tester);
      expect(host.room, NeuraRoom.dreamAtrium);
      expect(host.visits, ['her_suite', 'dream_atrium']);
    });

    testWidgets('only one visit opens at a time', (tester) async {
      await openSuite(tester);
      expect(HerSuiteScreen.visiting, isTrue);
      final context = tester.element(find.text('Her Suite'));
      await HerSuiteScreen.open(context);
      await tester.pumpAndSettle();
      expect(find.byType(HerSuiteScreen), findsOneWidget);
      await back(tester);
      expect(HerSuiteScreen.visiting, isFalse);
    });

    testWidgets('unreadable taught settings are not shown as untaught',
        (tester) async {
      shelf.set(_unreadable);
      await openSuite(tester);
      await tester.tap(find.byKey(const ValueKey('her-suite-shelf')));
      await tester.pumpAndSettle();
      expect(find.text('Could not be read'), findsNWidgets(2));
      expect(find.text('Not taught yet'), findsNothing);
    });

    testWidgets('a short screen scrolls instead of overflowing',
        (tester) async {
      tester.view.physicalSize = const Size(480, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await openSuite(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('her-suite-shelf')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('her-shelf-memories')),
        100,
      );
      expect(
        find.byKey(const ValueKey('her-shelf-memories')).hitTestable(),
        findsOneWidget,
      );
    });

    testWidgets('Safe Mode wakes her and leaves the resting screen',
        (tester) async {
      await openSuite(tester);
      await tester.tap(find.byKey(const ValueKey('her-suite-rest')));
      await tester.pumpAndSettle();
      safeMode.value = true;
      await tester.pumpAndSettle();
      expect(controller.resting, isFalse);
      expect(find.text('Resting'), findsNothing);
      expect(find.text('Not in Safe Mode'), findsOneWidget);
    });
  });
}
