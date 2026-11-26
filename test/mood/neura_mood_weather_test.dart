import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/modules/mood/mood_models.dart';
import 'package:neuro_companion/mood/services/neura_mood_weather.dart';
import 'package:neuro_companion/neura_shell/widgets/neura_penthouse_scene.dart';

void main() {
  final now = DateTime(2026, 11, 20, 12);
  List<MoodEntry> week(List<int> moods, {int daysAgo = 0}) => [
        for (var i = 0; i < moods.length; i++)
          MoodEntry(
            timestamp: now.subtract(Duration(days: daysAgo + i)),
            mood0to10: moods[i],
            note: '',
          ),
      ];

  test('the week sets the weather; thin data stays mild', () {
    expect(NeuraMoodWeather.from(week([8, 7, 9]), now), NeuraMoodWeather.clear);
    expect(NeuraMoodWeather.from(week([6, 5, 6]), now), NeuraMoodWeather.mild);
    expect(
        NeuraMoodWeather.from(week([4, 4, 5]), now), NeuraMoodWeather.overcast);
    expect(NeuraMoodWeather.from(week([2, 3, 1]), now), NeuraMoodWeather.rain);
    expect(NeuraMoodWeather.from(week([1, 1]), now), NeuraMoodWeather.mild);
    expect(NeuraMoodWeather.from(const [], now), NeuraMoodWeather.mild);
  });

  test('only the last seven days count', () {
    final old = week([1, 1, 1, 1], daysAgo: 8);
    expect(NeuraMoodWeather.from(old, now), NeuraMoodWeather.mild);
    final mixed = [
      ...old,
      ...week([8, 8, 8])
    ];
    expect(NeuraMoodWeather.from(mixed, now), NeuraMoodWeather.clear);
  });

  test('a change of weather repaints the room', () {
    NeuraPenthousePainter painter(NeuraMoodWeather weather) =>
        NeuraPenthousePainter(
          overlay: Colors.transparent,
          showFurniture: true,
          weather: weather,
        );
    expect(
      painter(NeuraMoodWeather.rain)
          .shouldRepaint(painter(NeuraMoodWeather.mild)),
      isTrue,
    );
    expect(
      painter(NeuraMoodWeather.rain)
          .shouldRepaint(painter(NeuraMoodWeather.rain)),
      isFalse,
    );
  });

  testWidgets('every weather paints without errors', (tester) async {
    for (final weather in NeuraMoodWeather.values) {
      await tester.pumpWidget(MaterialApp(
        home: NeuraPenthouseScene(weather: weather),
      ));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the scene follows the shared weather by default', (
    tester,
  ) async {
    final service = NeuraMoodWeatherService.instance;
    addTearDown(service.reset);
    await tester.pumpWidget(const MaterialApp(home: NeuraPenthouseScene()));
    NeuraPenthousePainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<NeuraPenthousePainter>()
        .single;
    expect(painter().weather, NeuraMoodWeather.mild);
    service.weather.value = NeuraMoodWeather.rain;
    await tester.pumpAndSettle();
    expect(painter().weather, NeuraMoodWeather.rain);
  });
}
