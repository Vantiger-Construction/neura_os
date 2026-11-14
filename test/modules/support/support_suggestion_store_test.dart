import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/memory_crypto.dart';
import 'package:neuro_companion/modules/support/guided_support_activity.dart';
import 'package:neuro_companion/modules/support/guided_support_store.dart';
import 'package:neuro_companion/modules/support/support_suggestion_choices.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final values = <String, String>{};
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          return values[key];
        case 'write':
          values[key] = args['value'] as String;
          return null;
        case 'delete':
          values.remove(key);
          return null;
        case 'containsKey':
          return values.containsKey(key);
      }
      throw StateError('Unexpected secure-storage call');
    });
  });
  setUp(() async {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
    await NeuraPrefsCache.prefs.clear();
  });
  tearDown(() {
    SafeBoot.instance.safeMode.value = false;
    SafeBoot.instance.restartRequired.value = false;
  });
  tearDownAll(() =>
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test(
      'default read does not create a key and confirmed choices reopen encrypted',
      () async {
    final store = GuidedSupportStore();
    expect((await store.readChoices()).onlyWhenAsked, isFalse);
    expect(NeuraPrefsCache.prefs.getKeys(), isEmpty);
    final choices = SupportSuggestionChoices(
        onlyWhenAsked: true, excluded: {GuidedSupportActivity.gentleBreathing});
    await store.saveChoicesAfterConfirmation(choices,
        stillApproved: () => true);
    final raw = NeuraPrefsCache.prefs.getString(GuidedSupportStore.choicesKey)!;
    expect(raw, isNot(contains('gentleBreathing')));
    expect(
        (await GuidedSupportStore().readChoices()).toJson(), choices.toJson());
  });
  test('forgetting choices preserves the separately remembered activity',
      () async {
    final store = GuidedSupportStore();
    await store.rememberAfterConfirmation(GuidedSupportActivity.grounding,
        stillApproved: () => true);
    await store.saveChoicesAfterConfirmation(
        SupportSuggestionChoices(onlyWhenAsked: true),
        stillApproved: () => true);
    await store.forgetChoices();
    expect((await store.read())!.activity, GuidedSupportActivity.grounding);
    expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.choicesKey),
        isFalse);
  });
  test('revoked approval and recovery reject writes before cryptography',
      () async {
    var cryptoCalls = 0;
    final store = GuidedSupportStore(loadCrypto: () {
      cryptoCalls++;
      throw StateError('Forbidden');
    });
    await expectLater(
        store.saveChoicesAfterConfirmation(SupportSuggestionChoices(),
            stillApproved: () => false),
        throwsStateError);
    SafeBoot.instance.restartRequired.value = true;
    await expectLater(
        store.saveChoicesAfterConfirmation(SupportSuggestionChoices(),
            stillApproved: () => true),
        throwsStateError);
    expect(cryptoCalls, 0);
  });
  test('approval revoked during encryption admission leaves no saved choices',
      () async {
    final crypto = await MemoryCrypto.demo();
    final gate = Completer<MemoryCrypto>();
    var approved = true;
    final store = GuidedSupportStore(loadCrypto: () => gate.future);
    final pending = store.saveChoicesAfterConfirmation(
        SupportSuggestionChoices(onlyWhenAsked: true),
        stillApproved: () => approved);
    await Future<void>.delayed(Duration.zero);
    approved = false;
    final assertion = expectLater(pending, throwsStateError);
    gate.complete(crypto);
    await assertion;
    expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.choicesKey),
        isFalse);
  });
  test('wipe drains a pending writer and removes both preference keys',
      () async {
    final crypto = await MemoryCrypto.demo();
    final existing = GuidedSupportStore();
    await existing.rememberAfterConfirmation(GuidedSupportActivity.grounding,
        stillApproved: () => true);
    await existing.saveChoicesAfterConfirmation(
        SupportSuggestionChoices(onlyWhenAsked: true),
        stillApproved: () => true);
    final gate = Completer<MemoryCrypto>();
    final store = GuidedSupportStore(loadCrypto: () => gate.future);
    final pending = store.saveChoicesAfterConfirmation(
        SupportSuggestionChoices(),
        stillApproved: () => true);
    await Future<void>.delayed(Duration.zero);
    final assertion = expectLater(pending, throwsStateError);
    final wipe = store.resetAfterDataWipe();
    gate.complete(crypto);
    await assertion;
    await wipe;
    expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.choicesKey),
        isFalse);
    expect(NeuraPrefsCache.prefs.containsKey(GuidedSupportStore.storageKey),
        isFalse);
  });
  test('corrupt choices fail closed rather than silently enabling suggestions',
      () async {
    final crypto = await MemoryCrypto.demo();
    await NeuraPrefsCache.prefs.setString(GuidedSupportStore.choicesKey,
        await crypto.encryptJson({'version': 1, 'scope': 'wrong'}));
    await expectLater(
        GuidedSupportStore().readChoices(), throwsFormatException);
  });
}
