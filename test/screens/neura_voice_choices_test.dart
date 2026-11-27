import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/screens/neura_voice_settings_screen.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

class _SettingsTts extends FlutterTts {
  final selections = <Map<String, String>>[];
  final rates = <double>[];
  int spoken = 0;
  int stops = 0;
  bool reject = false;
  List<dynamic> voices = [
    {
      'name': 'Sample voice',
      'locale': 'en-US',
      'gender': 'female',
      'network_required': '0'
    },
    {
      'name': 'Sample voice',
      'locale': 'en-GB',
      'gender': 'female',
      'network_required': '0'
    },
    {
      'name': 'Sample deeper voice',
      'locale': 'en-AU',
      'gender': 'male',
      'network_required': '0'
    },
  ];
  @override
  Future<dynamic> get getVoices async => voices;
  @override
  Future<dynamic> setVoice(Map<String, String> voice) async {
    selections.add(Map.of(voice));
    return reject ? 0 : 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    rates.add(rate);
    return 1;
  }

  @override
  Future<dynamic> setPitch(double pitch) async => 1;
  @override
  Future<dynamic> setVolume(double volume) async => 1;
  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken++;
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    stops++;
    return 1;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _SettingsTts native;
  late NeuraTtsService service;
  late bool safe;
  late bool restart;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });
  setUp(() async {
    await NeuraPrefsCache.prefs.clear();
    safe = SafeBoot.instance.safeMode.value;
    restart = SafeBoot.instance.restartRequired.value;
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    native = _SettingsTts();
    service = NeuraTtsService.forTesting(native);
  });
  tearDown(() async {
    await service.dispose();
    SafeBoot.instance.safeMode.value = safe;
    SafeBoot.instance.restartRequired.value = restart;
  });

  Future<void> show(WidgetTester tester,
      {double scale = 1, double width = 800}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: NeuraVoiceSettingsScreen(service: service),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
    }
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 220,
          scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  void settingsTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      final platform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(tester);
      } finally {
        await close(tester);
        debugDefaultTargetPlatformOverride = platform;
      }
    });
  }

  settingsTest('accent browsing does not silently select a voice',
      (tester) async {
    await show(tester);
    final filter = find.byKey(const Key('voice-accent-filter'));
    await reveal(tester, filter);
    native.selections.clear();
    await tester.tap(filter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('British English').last);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('voice-en-gb:Sample voice')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('voice-en-us:Sample voice')), findsNothing);
    expect(native.selections, isEmpty);
    final british = find.byKey(const ValueKey('voice-en-gb:Sample voice'));
    await reveal(tester, british);
    await tester.tap(british);
    await tester.pumpAndSettle();
    expect(native.selections.last['locale'], 'en-GB');
    expect(
        find.text('Selected: Sample voice · British English'), findsOneWidget);
    expect(NeuraPrefsCache.prefs.getString('neura.tts.voice_locale'), 'en-GB');
    await close(tester);
  });

  settingsTest('speed presets update slider, engine and saved preference',
      (tester) async {
    await show(tester);
    for (final preset in const [
      ('slower', .35),
      ('normal', .5),
      ('faster', .65)
    ]) {
      final chip = find.byKey(ValueKey('speech-speed-${preset.$1}'));
      await reveal(tester, chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Slider>(find.byKey(const Key('speech-rate-slider')))
              .value,
          preset.$2);
      expect(
          NeuraPrefsCache.prefs.getDouble('neura.tts.speech_rate'), preset.$2);
      expect(native.rates.last, preset.$2);
    }
    expect(native.spoken, 0);
    await close(tester);
  });

  settingsTest(
      'Stop sample restores the selected voice without saving the preview',
      (tester) async {
    await show(tester);
    final british = find.byKey(const ValueKey('voice-en-gb:Sample voice'));
    await reveal(tester, british);
    await tester.tap(find.descendant(
        of: british, matching: find.byTooltip('Play a sample')));
    await tester.pumpAndSettle();
    expect(native.spoken, 1);
    final stop = find.byKey(const Key('stop-voice-sample'));
    await reveal(tester, stop);
    await tester.tap(stop);
    await tester.pumpAndSettle();
    expect(native.selections.last['locale'], 'en-US');
    expect(NeuraPrefsCache.prefs.getString('neura.tts.voice_locale'), isNull);
    expect(tester.widget<OutlinedButton>(stop).onPressed, isNull);
    await close(tester);
  });

  settingsTest('backgrounding stops samples with no foreground replay',
      (tester) async {
    await show(tester);
    final british = find.byKey(const ValueKey('voice-en-gb:Sample voice'));
    await reveal(tester, british);
    await tester.tap(find.descendant(
        of: british, matching: find.byTooltip('Play a sample')));
    await tester.pumpAndSettle();
    final stops = native.stops;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(native.stops, greaterThan(stops));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(native.spoken, 1);
    expect(native.selections.last['locale'], 'en-US',
        reason:
            'Returning restores the chosen voice without replaying a sample.');
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  settingsTest('a rejected voice keeps the previous selection visible',
      (tester) async {
    await show(tester);
    native.reject = true;
    final british = find.byKey(const ValueKey('voice-en-gb:Sample voice'));
    await reveal(tester, british);
    await tester.tap(british);
    await tester.pumpAndSettle();
    expect(find.text('That voice could not be selected.'), findsOneWidget);
    expect(
        find.text('Selected: Sample voice · American English'), findsOneWidget);
    await close(tester);
  });

  settingsTest('restart-required disables samples', (tester) async {
    await show(tester);
    SafeBoot.instance.restartRequired.value = true;
    await tester.pumpAndSettle();
    final british = find.byKey(const ValueKey('voice-en-gb:Sample voice'));
    await reveal(tester, british);
    final play =
        find.descendant(of: british, matching: find.byType(IconButton));
    expect(tester.widget<IconButton>(play).onPressed, isNull);
    expect(native.spoken, 0);
    await close(tester);
  });

  settingsTest('compact windows and doubled text keep controls usable',
      (tester) async {
    await show(tester, scale: 2, width: 360);
    final filter = find.byKey(const Key('voice-accent-filter'));
    await reveal(tester, filter);
    expect(tester.takeException(), isNull);
    final voice = find.byKey(const ValueKey('voice-en-gb:Sample voice'));
    await reveal(tester, voice);
    expect(tester.takeException(), isNull);
    final slower = find.byKey(const ValueKey('speech-speed-slower'));
    await reveal(tester, slower);
    await tester.tap(slower);
    await tester.pumpAndSettle();
    expect(service.speechRate, .35);
    expect(tester.takeException(), isNull);
    await close(tester);
  });
}
