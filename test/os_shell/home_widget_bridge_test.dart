import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_companion/modules/mood/mood_models.dart';
import 'package:neuro_companion/modules/mood/mood_store.dart';
import 'package:neuro_companion/os_shell/widgets_bridge/home_widget_bridge.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('home_widget');
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final calls = <MethodCall>[];
  final secureStorage = <String, String>{};

  Map<String, Object?> savedData() {
    final data = <String, Object?>{};
    for (final call in calls) {
      if (call.method == 'saveWidgetData') {
        data[call.arguments['id'] as String] = call.arguments['data'];
      }
    }
    return data;
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });

  setUp(() {
    calls.clear();
    SafeBoot.instance.safeMode.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    // MoodStore encrypts entries via MemoryCrypto, which stores its key
    // through flutter_secure_storage -- fake just enough of that channel
    // for MoodStore.add()/latest() to work in a unit test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final key = (call.arguments as Map?)?['key'] as String?;
      switch (call.method) {
        case 'write':
          if (key != null) {
            secureStorage[key] = (call.arguments as Map)['value'] as String;
          }
          return null;
        case 'read':
          return key == null ? null : secureStorage[key];
        case 'containsKey':
          return key != null && secureStorage.containsKey(key);
        case 'delete':
          if (key != null) secureStorage.remove(key);
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    SafeBoot.instance.safeMode.value = false;
  });

  test('refresh pushes a blank, safe-mode snapshot while Safe Mode is active',
      () async {
    SafeBoot.instance.safeMode.value = true;
    await HomeWidgetBridge.instance.refresh();

    final data = savedData();
    expect(data['neura_widget_safe_mode'], '1');
    expect(data['neura_widget_mood_value'], '');
    expect(data['neura_widget_nudge_title'], '');
    expect(calls.any((c) => c.method == 'updateWidget'), isTrue);
  });

  test('refresh mirrors the most recently saved mood entry', () async {
    await MoodStore.instance.add(
      MoodEntry(timestamp: DateTime.now(), mood0to10: 6, note: ''),
    );
    calls.clear();

    await HomeWidgetBridge.instance.refresh();

    final data = savedData();
    expect(data['neura_widget_mood_value'], '6');
    expect(data['neura_widget_safe_mode'], '0');
  });

  test('mirrorApprovedNudge is reflected on its own refresh', () async {
    HomeWidgetBridge.instance.mirrorApprovedNudge(
      'A gentle reset is available',
    );
    // mirrorApprovedNudge fires an internal, unawaited refresh.
    await Future<void>.delayed(Duration.zero);

    expect(
      savedData()['neura_widget_nudge_title'],
      'A gentle reset is available',
    );

    HomeWidgetBridge.instance.mirrorApprovedNudge(null);
    await Future<void>.delayed(Duration.zero);
    expect(savedData()['neura_widget_nudge_title'], '');
  });

  test('a missing platform implementation never throws', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    await expectLater(HomeWidgetBridge.instance.refresh(), completes);
  });
}
