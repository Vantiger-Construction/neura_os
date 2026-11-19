import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/avatar_controller.dart';
import 'package:neuro_companion/avatar/avatar_registry.dart';
import 'package:neuro_companion/avatar/avatar_types.dart';
import 'package:neuro_companion/avatar/avatar_view.dart';
import 'package:neuro_companion/avatar/motion/neura_motion.dart';
import 'package:neuro_companion/avatar/renderers/nebula_avatar_view.dart';
import 'package:neuro_companion/avatar/renderers/neura_mouth_layer.dart';
import 'package:neuro_companion/core/neura_events_extra.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/screens/avatar_selector_screen.dart';
import 'package:neuro_companion/services/avatar_service.dart';
import 'package:neuro_companion/services/neura_companion_presence.dart';
import 'package:neuro_companion/src/shell/shell_prefs.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const nebula = AvatarRegistry.nebulaId;
  late ShellPrefs originalPrefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });
  setUp(() async {
    originalPrefs = ShellPrefsController.instance.prefs.value;
    NeuraMotion.instance.stop();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    ShellPrefsController.instance.prefs.value = ShellPrefs.defaults;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await NeuraPrefsCache.prefs.clear();
    AvatarService.instance.resetForTesting();
  });
  tearDown(() {
    NeuraMotion.instance.stop();
    AvatarService.instance.resetAfterDataWipe();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    ShellPrefsController.instance.prefs.value = originalPrefs;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  Widget avatar(AvatarController controller, {bool reduceMotion = false}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Center(
            child: AvatarView(
              spec: AvatarRegistry.byId(nebula),
              controller: controller,
              animateBody: false,
            ),
          ),
        ),
      );

  NeuraNebulaPainter painter(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<NeuraNebulaPainter>()
      .single;

  test('nebula is a built-in avatar with no asset', () {
    final spec = AvatarRegistry.byId(nebula);
    expect(spec.id, nebula);
    expect(spec.format, AvatarFormat.nebula);
    expect(spec.assetPath, isEmpty);
  });

  testWidgets('time holds still until motion is live, and again on Still',
      (tester) async {
    final controller = AvatarController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(avatar(controller));
    await tester.pump();
    expect(find.byType(NebulaAvatarView), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(painter(tester).seconds.value, 0);

    NeuraMotion.instance.start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 500));
    final moving = painter(tester).seconds.value;
    expect(moving, greaterThan(0));

    ShellPrefsController.instance.prefs.value = ShellPrefs.defaults
        .copyWith(companionMotion: NeuraCompanionMotion.still);
    await tester.pump();
    final held = painter(tester).seconds.value;
    expect(held, greaterThanOrEqualTo(moving));
    await tester.pump(const Duration(seconds: 1));
    expect(painter(tester).seconds.value, held);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion keeps her still even when motion is live',
      (tester) async {
    final controller = AvatarController();
    addTearDown(controller.dispose);
    NeuraMotion.instance.start();
    await tester.pumpWidget(avatar(controller, reduceMotion: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(painter(tester).seconds.value, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mouth of light follows a fresh utterance and rests on Still',
      (tester) async {
    final controller = AvatarController();
    addTearDown(controller.dispose);
    NeuraMotion.instance.start();
    await tester.pumpWidget(avatar(controller));
    await tester.pump();
    NeuraMouthPose pose() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<NebulaMouthPainter>()
        .single
        .pose;
    void start() {
      controller.setTalking(false);
      controller.setTalking(true);
      controller.setNumberInput('viseme', NeuraViseme.AI.index.toDouble());
      controller.setNumberInput('mouthOpen', 0.6);
    }

    expect(pose(), NeuraMouthPose.rest);
    start();
    await tester.pump();
    expect(pose().open, 0.6);
    ShellPrefsController.instance.prefs.value = ShellPrefs.defaults
        .copyWith(companionMotion: NeuraCompanionMotion.still);
    await tester.pump();
    expect(pose(), NeuraMouthPose.rest);
    ShellPrefsController.instance.prefs.value = ShellPrefs.defaults;
    await tester.pump();
    controller.setNumberInput('mouthOpen', 0.8);
    await tester.pump();
    expect(pose(), NeuraMouthPose.rest);
    start();
    await tester.pump();
    expect(pose().open, 0.6);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('selector previews the nebula still and saves the choice',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AvatarSelectorScreen()));
    await tester.pumpAndSettle();
    final preview = find.byType(NebulaAvatarView);
    expect(preview, findsOneWidget);
    expect(tester.widget<NebulaAvatarView>(preview).enabled, isFalse);
    await tester.tap(find.byKey(const ValueKey(nebula)));
    await tester.pumpAndSettle();
    expect(AvatarService.instance.selectedAvatarId.value, nebula);
    await tester.pumpWidget(const SizedBox());
  });
}
