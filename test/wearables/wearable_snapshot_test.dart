import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/wearables/wearable_snapshot.dart';

final now = DateTime.utc(2026, 11, 16, 10);
Map<String, Object?> payload() => {
      'schema': 1,
      'fromMs': now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch,
      'toMs': now.millisecondsSinceEpoch,
      'metrics': <String, Object?>{
        'heart_rate': <String, Object?>{
          'status': 'data',
          'value': 72,
          'atMs':
              now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch,
          'sources': ['com.example.synthetic'],
          'recording': 'manual',
          'partial': true,
        },
        'steps': <String, Object?>{
          'status': 'data',
          'value': 0,
          'sources': ['com.example.synthetic'],
          'partial': false,
        },
        'sleep': <String, Object?>{
          'status': 'data',
          'startMs':
              now.subtract(const Duration(hours: 10)).millisecondsSinceEpoch,
          'endMs':
              now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
          'sources': ['com.example.synthetic'],
          'recording': 'automatic',
          'partial': false,
        },
      },
    };

Map<String, Object?> metric(Map<String, Object?> p, String key) =>
    (p['metrics']! as Map<String, Object?>)[key]! as Map<String, Object?>;

WearableSnapshot parse(Map<String, Object?> p) =>
    WearableSnapshot.fromPlatform(p,
        requested: WearableMetric.values.toSet(), now: now);

void main() {
  test(
      'describes provenance, stale sample, partial/manual input and sleep span',
      () {
    final value = parse(payload());
    final heart = value.readings[WearableMetric.heartRate]!.describe();
    expect(heart, contains('72 bpm at 2026-11-16T09:40:00.000Z'));
    expect(heart, contains('com.example.synthetic'));
    expect(heart, contains('manual'));
    expect(heart, contains('Limited'));
    final sleep = value.readings[WearableMetric.sleep]!.describe();
    expect(sleep, contains('480 minutes'));
    expect(sleep, contains('not time asleep'));
    expect(value.readings[WearableMetric.steps]!.describe(), contains(': 0.'));
  });

  test('absent data and missing permission never become a zero reading', () {
    final p = payload();
    final readings = p['metrics']! as Map<String, Object?>;
    readings['steps'] = {'status': 'no_data'};
    readings['heart_rate'] = {'status': 'permission_required'};
    final value = parse(p);
    expect(value.readings[WearableMetric.steps]!.value, isNull);
    expect(
        value.readings[WearableMetric.steps]!.describe(), contains('not zero'));
    expect(value.readings[WearableMetric.heartRate]!.hasData, isFalse);
    expect(() => value.selectedText({WearableMetric.steps}),
        throwsFormatException);
  });

  test('review contains only selected readings; immutable parsed state', () {
    final p = payload();
    final snapshot = parse(p);
    metric(p, 'heart_rate')['value'] = 100;
    final text = snapshot.selectedText({WearableMetric.heartRate});
    expect(text, contains('72 bpm'));
    expect(text, isNot(contains('Aggregated steps')));
    expect(text, isNot(contains('Sleep session window')));
    expect(() => snapshot.readings.clear(), throwsUnsupportedError);
    expect(() => snapshot.selectedText({}), throwsFormatException);
  });

  final invalid = <String, void Function(Map<String, Object?>)>{
    'unknown schema': (p) => p['schema'] = 2,
    'wrong window': (p) => p['fromMs'] = now.millisecondsSinceEpoch,
    'future window': (p) {
      p['fromMs'] =
          now.subtract(const Duration(hours: 23)).millisecondsSinceEpoch;
      p['toMs'] = now.add(const Duration(hours: 1)).millisecondsSinceEpoch;
    },
    'expired response': (p) {
      p['fromMs'] =
          now.subtract(const Duration(hours: 25)).millisecondsSinceEpoch;
      p['toMs'] = now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    },
    'float time': (p) => p['toMs'] = 123.5,
    'unrequested metric': (p) =>
        (p['metrics']! as Map)['diagnosis'] = {'status': 'data'},
    'missing selected metric': (p) => (p['metrics']! as Map).remove('steps'),
    'clinical conclusion': (p) => metric(p, 'heart_rate')['diagnosis'] = 'well',
    'raw sleep notes': (p) => metric(p, 'sleep')['notes'] = 'private',
    'malformed source': (p) =>
        metric(p, 'steps')['sources'] = ['text\ninjection'],
    'missing source field': (p) => metric(p, 'steps').remove('sources'),
    'invalid heart rate': (p) => metric(p, 'heart_rate')['value'] = 0,
    'noninteger steps': (p) => metric(p, 'steps')['value'] = 1.5,
    'negative steps': (p) => metric(p, 'steps')['value'] = -1,
    'out of window sample': (p) => metric(p, 'heart_rate')['atMs'] =
        now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
    'unknown recording method': (p) =>
        metric(p, 'heart_rate')['recording'] = 'doctor-verified',
    'missing partial flag': (p) => metric(p, 'heart_rate').remove('partial'),
    'reversed sleep times': (p) => metric(p, 'sleep')['startMs'] =
        now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
    'extra data on denied permission': (p) =>
        metric(p, 'steps')['status'] = 'permission_required',
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key} without a clinical fallback', () {
      final p = payload();
      entry.value(p);
      expect(() => parse(p), throwsFormatException);
    });
  }

  test('does not accept extra granted data when only steps were requested', () {
    expect(
        () => WearableSnapshot.fromPlatform(payload(),
            requested: {WearableMetric.steps}, now: now),
        throwsFormatException);
  });
}
