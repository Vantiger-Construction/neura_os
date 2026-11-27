import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/services/neura_tts_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';

class _CatalogTts extends FlutterTts {
  List<dynamic> voices = [];
  final selections = <Map<String, String>>[];
  Completer<int>? voiceGate;
  int selectionResult = 1;
  @override
  Future<dynamic> get getVoices async => voices;
  @override
  Future<dynamic> setVoice(Map<String, String> voice) async {
    selections.add(Map.of(voice));
    return voiceGate == null ? selectionResult : voiceGate!.future;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;
  @override
  Future<dynamic> setPitch(double pitch) async => 1;
  @override
  Future<dynamic> setVolume(double volume) async => 1;
  @override
  Future<dynamic> stop() async => 1;
}

Map<String, Object> _voice(String name, String locale,
        {Object network = '0', String features = ''}) =>
    {
      'name': name,
      'locale': locale,
      'gender': 'female',
      'network_required': network,
      'features': features,
    };

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _CatalogTts native;
  late NeuraTtsService service;
  late bool safe;
  late TargetPlatform? platform;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
  });
  setUp(() async {
    await NeuraPrefsCache.prefs.clear();
    safe = SafeBoot.instance.safeMode.value;
    SafeBoot.instance.safeMode.value = false;
    platform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    native = _CatalogTts();
    service = NeuraTtsService.forTesting(native);
  });
  tearDown(() async {
    await service.dispose();
    debugDefaultTargetPlatformOverride = platform;
    SafeBoot.instance.safeMode.value = safe;
  });

  test('accent labels normalize separators and preserve unknown variants', () {
    const british =
        NeuraVoiceOption(name: 'Sample', locale: 'en_GB', gender: 'unknown');
    const american =
        NeuraVoiceOption(name: 'Sample', locale: 'en-US', gender: 'unknown');
    const other =
        NeuraVoiceOption(name: 'Sample', locale: 'en-JM', gender: 'unknown');
    expect(british.accentLabel, 'British English');
    expect(american.accentLabel, 'American English');
    expect(other.accentLabel, 'English (en-JM)');
    expect(british.id, isNot(american.id));
  });

  test('catalog keeps same-named accents and rejects malformed duplicates',
      () async {
    native.voices = [
      _voice('Sample', 'en-US'),
      _voice('Sample', 'en-GB'),
      _voice('Sample', 'en-GB'),
      _voice('', 'en-US'),
      _voice('French sample', 'fr-FR'),
      _voice('Invalid language', 'english'),
      null,
      'malformed',
    ];
    final options = await service.availableVoices();
    expect(options.map((v) => v.accentLabel),
        ['American English', 'British English']);
    expect(options.map((v) => v.id).toSet(), hasLength(2));
  });

  test('Android catalog excludes network, unknown and not-installed voices',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native.voices = [
      _voice('Local American', 'en-US'),
      _voice('Local Australian', 'en-AU', network: false),
      _voice('Network British', 'en-GB', network: '1'),
      _voice('Missing Indian', 'en-IN', features: 'notInstalled'),
      {'name': 'Unknown network status', 'locale': 'en-IE'},
    ];
    final options = await service.availableVoices();
    expect(options.map((v) => v.name), ['Local American', 'Local Australian']);
    expect(options.map((v) => v.accentKey), isNot(contains('en-gb')));
  });

  test('selected name and locale are both saved and restored', () async {
    native.voices = [
      _voice('Same name', 'en-US'),
      _voice('Same name', 'en-GB')
    ];
    final options = await service.availableVoices();
    await service.setVoice(options.singleWhere((v) => v.locale == 'en-GB'));
    expect(
        NeuraPrefsCache.prefs.getString('neura.tts.voice_name'), 'Same name');
    expect(NeuraPrefsCache.prefs.getString('neura.tts.voice_locale'), 'en-GB');
    expect(service.selectedVoiceLocale, 'en-GB');
    await service.dispose();
    service = NeuraTtsService.forTesting(native);
    await service.warmUp();
    expect(service.selectedVoiceName, 'Same name');
    expect(service.selectedVoiceLocale, 'en-GB');
    expect(native.selections.last['locale'], 'en-GB');
  });

  test('Android startup preserves a same-named voice in the chosen accent',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native.voices = [
      _voice('Same name', 'en-US'),
      _voice('Same name', 'en-GB')
    ];
    final options = await service.availableVoices();
    await service.setVoice(options.singleWhere((v) => v.locale == 'en-GB'));
    await service.prepareLocalStartupVoice();
    expect(native.selections.last['locale'], 'en-GB');
    expect(service.selectedVoiceLocale, 'en-GB');
  });

  test('rejected native voice keeps the previous selection', () async {
    native.voices = [_voice('American', 'en-US'), _voice('British', 'en-GB')];
    await service.warmUp();
    native.selectionResult = 0;
    await service.setVoice(const NeuraVoiceOption(
        name: 'British', locale: 'en-GB', gender: 'female'));
    expect(service.selectedVoiceName, 'American');
    expect(service.selectedVoiceLocale, 'en-US');
    expect(NeuraPrefsCache.prefs.getString('neura.tts.voice_name'), isNull);
  });

  test('a late selection after Stop is not persisted', () async {
    native.voices = [_voice('American', 'en-US')];
    await service.warmUp();
    native.voiceGate = Completer<int>();
    final selection = service.setVoice(const NeuraVoiceOption(
        name: 'British', locale: 'en-GB', gender: 'female'));
    await Future<void>.delayed(Duration.zero);
    await service.stop();
    native.voiceGate!.complete(1);
    await selection;
    expect(service.selectedVoiceLocale, 'en-US');
    expect(NeuraPrefsCache.prefs.getString('neura.tts.voice_locale'), isNull);
    native.voiceGate = null;
  });

  test('speaking speed survives a new service and retains existing bounds',
      () async {
    await service.setSpeechRate(0.65);
    expect(NeuraPrefsCache.prefs.getDouble('neura.tts.speech_rate'), 0.65);
    await service.dispose();
    service = NeuraTtsService.forTesting(native);
    await service.warmUp();
    expect(service.speechRate, 0.65);
    await service.setSpeechRate(100);
    expect(service.speechRate, 0.75);
    await service.setSpeechRate(-100);
    expect(service.speechRate, 0.25);
  });

  test('Safe Mode blocks catalog initialization and voice selection', () async {
    SafeBoot.instance.safeMode.value = true;
    native.voices = [_voice('American', 'en-US')];
    expect(await service.availableVoices(), isEmpty);
    await service.setVoice(const NeuraVoiceOption(
        name: 'American', locale: 'en-US', gender: 'female'));
    expect(native.selections, isEmpty);
  });
}
