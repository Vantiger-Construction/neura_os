import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/avatar_controller.dart';
import 'package:neuro_companion/avatar/avatar_registry.dart';
import 'package:neuro_companion/avatar/avatar_view.dart';
import 'package:neuro_companion/avatar/motion/neura_motion.dart';
import 'package:neuro_companion/avatar/renderers/flutter_mouth_avatar_view.dart';
import 'package:neuro_companion/avatar/renderers/neura_mouth_layer.dart';
import 'package:neuro_companion/core/neura_events_extra.dart';
import 'package:neuro_companion/neura_shell/models/neura_room.dart';
import 'package:neuro_companion/neura_shell/widgets/neura_room_presence_avatar.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/screens/avatar_selector_screen.dart';
import 'package:neuro_companion/services/avatar_service.dart';
import 'package:neuro_companion/services/neura_companion_presence.dart';
import 'package:neuro_companion/src/shell/shell_prefs.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _ControlledPreferences extends SharedPreferencesStorePlatform {
  _ControlledPreferences(this.original, {this.pending});
  final SharedPreferencesStorePlatform original;
  final Completer<bool>? pending;
  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      pending?.future ?? Future.value(false);
  @override
  Future<Map<String, Object>> getAll() => original.getAll();
  @override
  Future<bool> clear() => original.clear();
  @override
  Future<bool> remove(String key) => original.remove(key);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final service = AvatarService.instance;
  const face = AvatarRegistry.expressiveFaceId;
  late SharedPreferencesStorePlatform original;
  late ShellPrefs originalPrefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });
  setUp(() async {
    original = SharedPreferencesStorePlatform.instance;
    originalPrefs = ShellPrefsController.instance.prefs.value;
    NeuraMotion.instance.stop();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    ShellPrefsController.instance.prefs.value = ShellPrefs.defaults;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await NeuraPrefsCache.prefs.clear();
    service.resetAfterDataWipe();
  });
  tearDown(() {
    SharedPreferencesStorePlatform.instance = original;
    NeuraMotion.instance.stop();
    service.resetAfterDataWipe();
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    ShellPrefsController.instance.prefs.value = originalPrefs;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  test('selection survives a fresh service load; unknown IDs stay on Neura',
      () async {
    expect(await service.selectAvatar(face), isTrue);
    final restarted = AvatarService();
    expect((await restarted.getSelectedAvatar()).id, face);
    expect(restarted.selectedAvatarId.value, face);
    expect(await service.selectAvatar('missing'), isFalse);
    await NeuraPrefsCache.prefs.setString('avatar_selected_id', 'missing');
    expect((await restarted.getSelectedAvatar()).id, 'neura');
    expect(restarted.selectedAvatarId.value, 'neura');
  });

  test('rejected save does not change the active or next loaded avatar',
      () async {
    SharedPreferencesStorePlatform.instance = _ControlledPreferences(original);
    expect(await service.selectAvatar(face), isFalse);
    expect(service.selectedAvatarId.value, 'neura');
    expect((await service.getSelectedAvatar()).id, 'neura');
  });

  test('pending selection stays unconfirmed and cannot revive after reset',
      () async {
    final pending = Completer<bool>();
    SharedPreferencesStorePlatform.instance =
        _ControlledPreferences(original, pending: pending);
    final saving = service.selectAvatar(face);
    expect(service.selectedAvatarId.value, 'neura');
    expect((await service.getSelectedAvatar()).id, 'neura');
    expect(await service.selectAvatar('neuro'), isFalse);
    service.resetAfterDataWipe();
    pending.complete(true);
    expect(await saving, isFalse);
    expect(service.selectedAvatarId.value, 'neura');
  });

  Widget room() => const SizedBox(
        height: 170,
        child: NeuraRoomPresenceAvatar(
          room: NeuraRoom.penthouse,
          phase: NeuraPresencePhase.idle,
          motion: NeuraCompanionMotion.subtle,
          scale: NeuraCompanionScale.standard,
        ),
      );

  testWidgets(
      'selector updates the already-mounted room and persists selection',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        room(),
        const Expanded(child: AvatarSelectorScreen()),
      ]),
    ));
    await tester.pumpAndSettle();
    final roomFace = find.descendant(
      of: find.byType(NeuraRoomPresenceAvatar),
      matching: find.byType(FlutterMouthAvatarView),
    );
    expect(roomFace, findsNothing);
    await tester.tap(find.byKey(const ValueKey(face)));
    await tester.pumpAndSettle();
    expect(service.selectedAvatarId.value, face);
    expect(roomFace, findsOneWidget);
    expect(tester.widget<ListTile>(find.byKey(const ValueKey(face))).selected,
        isTrue);
    await tester.pumpWidget(const SizedBox());
    service.resetAfterDataWipe();
    await service.init();
    await tester.pumpWidget(MaterialApp(home: room()));
    await tester.pumpAndSettle();
    expect(roomFace, findsOneWidget);
  });

  testWidgets('selector reports failed save and retains the previous checkmark',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AvatarSelectorScreen()));
    await tester.pumpAndSettle();
    SharedPreferencesStorePlatform.instance = _ControlledPreferences(original);
    await tester.tap(find.byKey(const ValueKey(face)));
    await tester.pumpAndSettle();
    expect(find.text('Could not save your avatar. Please try again.'),
        findsOneWidget);
    expect(
        tester.widget<ListTile>(find.byKey(const ValueKey('neura'))).selected,
        isTrue);
    expect(service.selectedAvatarId.value, 'neura');
  });

  for (final boundary in ['Still', 'recovery']) {
    testWidgets('normal avatar rests at $boundary until a fresh speech start',
        (tester) async {
      final controller = AvatarController();
      addTearDown(controller.dispose);
      NeuraMotion.instance.start();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: AvatarView(
            spec: AvatarRegistry.byId(face),
            controller: controller,
            animateBody: false,
          ),
        ),
      ));
      await tester.pump();
      NeuraMouthPose pose() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<NeuraMouthPainter>()
          .single
          .pose;
      void start() {
        controller.setTalking(false);
        controller.setTalking(true);
        controller.setNumberInput('viseme', NeuraViseme.AI.index.toDouble());
        controller.setNumberInput('mouthOpen', 0.6);
      }

      start();
      await tester.pump();
      expect(pose().open, 0.6);
      if (boundary == 'Still') {
        ShellPrefsController.instance.prefs.value = ShellPrefs.defaults
            .copyWith(companionMotion: NeuraCompanionMotion.still);
      } else {
        SafeBoot.instance.restartRequired.value = true;
      }
      await tester.pump();
      expect(pose(), NeuraMouthPose.rest);
      ShellPrefsController.instance.prefs.value = ShellPrefs.defaults;
      SafeBoot.instance.restartRequired.value = false;
      await tester.pump();
      controller.setNumberInput('mouthOpen', 0.8);
      await tester.pump();
      expect(pose(), NeuraMouthPose.rest);
      start();
      await tester.pump();
      expect(pose().open, 0.6);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
