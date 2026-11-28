import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/insights/screens/wellbeing_check_screen.dart';
import 'package:neuro_companion/insights/services/wellbeing_check_service.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<String> _seal(Map<String, dynamic> json) async =>
    'sealed:${base64Encode(utf8.encode(jsonEncode(json)))}';
Future<Map<String, dynamic>> _open(String blob) async =>
    jsonDecode(utf8.decode(base64Decode(blob.substring('sealed:'.length))))
        as Map<String, dynamic>;

void main() {
  var now = DateTime(2026, 11, 1, 9);
  var allowed = true;

  WellbeingCheckService service() => WellbeingCheckService(
        encrypt: _seal,
        decrypt: _open,
        now: () => now,
        allowed: () => allowed,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NeuraPrefsCache.init();
    await NeuraPrefsCache.prefs.clear();
    now = DateTime(2026, 11, 1, 9);
    allowed = true;
  });

  test('scores on the WHO-5 0-100 scale and reads the band', () {
    final result = WellbeingCheckResult(
      takenAt: now,
      answers: const [3, 3, 2, 2, 3],
    );
    expect(result.raw, 13);
    expect(result.percent, 52);
    expect(WellbeingBand.of(100), WellbeingBand.good);
    expect(WellbeingBand.of(51), WellbeingBand.good);
    expect(WellbeingBand.of(50), WellbeingBand.reduced);
    expect(WellbeingBand.of(29), WellbeingBand.reduced);
    expect(WellbeingBand.of(28), WellbeingBand.low);
    expect(WellbeingBand.of(0), WellbeingBand.low);
  });

  test('injected serialization and the 28-day offer cadence round-trip',
      () async {
    final check = service();
    expect(await check.isDue(), isTrue);

    await check.record(const [5, 4, 4, 3, 4]);
    final blob =
        NeuraPrefsCache.prefs.getString(WellbeingCheckService.storageKey)!;
    expect(blob, startsWith('sealed:'));
    expect(blob, isNot(contains('answers')));
    expect(await check.isDue(), isFalse);

    now = now.add(const Duration(days: 27));
    expect(await check.isDue(), isFalse);
    now = now.add(const Duration(days: 1));
    expect(await check.isDue(), isTrue);

    final history = await check.history();
    expect(history.single.percent, 80);
  });

  test('incomplete or out-of-range answers are refused', () async {
    final check = service();
    await expectLater(check.record(const [1, 2, 3]), throwsArgumentError);
    await expectLater(
      check.record(const [1, 2, 3, 4, 6]),
      throwsArgumentError,
    );
    expect(await check.history(), isEmpty);
  });

  test('only the most recent results are kept', () async {
    final check = service();
    for (var i = 0; i < WellbeingCheckService.maxResults + 3; i++) {
      now = now.add(const Duration(days: 30));
      await check.record(const [1, 1, 1, 1, 1]);
    }
    expect(
      (await check.history()).length,
      WellbeingCheckService.maxResults,
    );
  });

  test('profile sessions cannot read or save the check', () async {
    final check = service();
    await check.record(const [2, 2, 2, 2, 2]);
    allowed = false;
    expect(await check.history(), isEmpty);
    expect(await check.isDue(), isFalse);
    await expectLater(check.record(const [2, 2, 2, 2, 2]), throwsStateError);
  });

  testWidgets('answering every question shows the score', (tester) async {
    // Tall enough that the lazy list builds every question and the button.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final check = service();
    await tester.pumpWidget(MaterialApp(
      home: WellbeingCheckScreen(service: check),
    ));
    await tester.pumpAndSettle();

    final button =
        find.widgetWithText(FilledButton, 'Save check and see score');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    for (var i = 0; i < WellbeingCheckService.questions.length; i++) {
      final chip = find.byKey(ValueKey<String>('wellbeing-$i-4'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
    }
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('80 / 100'), findsOneWidget);
    expect(
        find.text(
            'Your answers describe more frequent wellbeing over these two weeks.'),
        findsOneWidget);
    expect((await check.history()).single.answers, [4, 4, 4, 4, 4]);
  });
}
