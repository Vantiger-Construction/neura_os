enum WearableMetric {
  heartRate('heart_rate', 'Heart rate'),
  steps('steps', 'Steps'),
  sleep('sleep', 'Sleep session');

  const WearableMetric(this.key, this.label);
  final String key;
  final String label;
}

class WearableReading {
  const WearableReading(
      {required this.metric,
      required this.status,
      this.value,
      this.at,
      this.start,
      this.end,
      this.sources = const [],
      this.recording = 'unknown',
      this.partial = false});
  final WearableMetric metric;
  final String status;
  final int? value;
  final DateTime? at;
  final DateTime? start;
  final DateTime? end;
  final List<String> sources;
  final String recording;
  final bool partial;
  bool get hasData => status == 'data';

  String describe() {
    if (status == 'permission_required') return 'Permission not granted.';
    if (!hasData) return 'No data supplied for this window; this is not zero.';
    final data = switch (metric) {
      WearableMetric.heartRate =>
        'Recorded heart rate: $value bpm at ${at!.toUtc().toIso8601String()}.',
      WearableMetric.steps => 'Aggregated steps in this window: $value.',
      WearableMetric.sleep =>
        'Sleep session window: ${start!.toUtc().toIso8601String()} to ${end!.toUtc().toIso8601String()} '
            '(${end!.difference(start!).inMinutes} minutes). Session span is not time asleep.',
    };
    return '$data\nSource apps: ${sources.isEmpty ? 'not supplied' : sources.join(', ')}. '
        '${metric == WearableMetric.steps ? 'Health Connect aggregate; phone and wearable sources may be included.' : 'Recording method: $recording.'}'
        '${partial ? '\nLimited record/sample set; not a complete or guaranteed latest reading.' : ''}';
  }
}

class WearableSnapshot {
  const WearableSnapshot(
      {required this.from, required this.to, required this.readings});
  final DateTime from;
  final DateTime to;
  final Map<WearableMetric, WearableReading> readings;

  /// Platform payloads are data, never permissions or clinical conclusions.
  factory WearableSnapshot.fromPlatform(Object? payload,
      {required Set<WearableMetric> requested, required DateTime now}) {
    Never invalid() =>
        throw const FormatException('Health data had an unsupported format.');
    if (payload is! Map || payload['schema'] != 1 || requested.isEmpty) {
      invalid();
    }
    DateTime stamp(Object? value) {
      if (value is! int || value < 0 || value > 4102444800000) invalid();
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }

    final from = stamp(payload['fromMs']);
    final to = stamp(payload['toMs']);
    if (to.difference(from) != const Duration(hours: 24) ||
        to.isAfter(now.toUtc().add(const Duration(seconds: 5))) ||
        now.toUtc().difference(to) > const Duration(minutes: 1)) {
      invalid();
    }
    final values = payload['metrics'];
    if (values is! Map ||
        values.length != requested.length ||
        values.keys
            .any((key) => !requested.any((metric) => metric.key == key))) {
      invalid();
    }
    final result = <WearableMetric, WearableReading>{};
    for (final metric in requested) {
      final raw = values[metric.key];
      if (raw is! Map ||
          !const {'data', 'no_data', 'permission_required'}
              .contains(raw['status'])) {
        invalid();
      }
      final status = raw['status'] as String;
      if (status != 'data') {
        if (raw.length != 1) invalid();
        result[metric] = WearableReading(metric: metric, status: status);
        continue;
      }
      final allowed = <String>{
        'status',
        'sources',
        'partial',
        if (metric != WearableMetric.steps) 'recording',
        if (metric == WearableMetric.sleep) ...['startMs', 'endMs'] else
          'value',
        if (metric == WearableMetric.heartRate) 'atMs'
      };
      if (raw.keys.any((key) => !allowed.contains(key))) invalid();
      final sources = raw['sources'];
      if (sources is! List ||
          sources.length > 32 ||
          sources.any((s) =>
              s is! String ||
              s.length > 255 ||
              !RegExp(r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+$')
                  .hasMatch(s))) {
        invalid();
      }
      if (raw['partial'] is! bool) invalid();
      final recording =
          metric == WearableMetric.steps ? 'aggregate' : raw['recording'];
      if (metric != WearableMetric.steps &&
          !const {'manual', 'automatic', 'active', 'unknown'}
              .contains(recording)) {
        invalid();
      }
      int? number;
      DateTime? at;
      DateTime? start;
      DateTime? end;
      if (metric == WearableMetric.sleep) {
        start = stamp(raw['startMs']);
        end = stamp(raw['endMs']);
        if (start.isBefore(from) || !end.isAfter(start) || end.isAfter(to)) {
          invalid();
        }
      } else {
        final value = raw['value'];
        if (value is! int ||
            value < (metric == WearableMetric.heartRate ? 1 : 0) ||
            value > (metric == WearableMetric.heartRate ? 300 : 1000000)) {
          invalid();
        }
        number = value;
        if (metric == WearableMetric.heartRate) {
          at = stamp(raw['atMs']);
          if (at.isBefore(from) || at.isAfter(to)) invalid();
        }
      }
      result[metric] = WearableReading(
          metric: metric,
          status: status,
          value: number,
          at: at,
          start: start,
          end: end,
          sources: List.unmodifiable(sources.cast<String>().toSet()),
          recording: recording as String,
          partial: raw['partial'] as bool);
    }
    return WearableSnapshot(
        from: from, to: to, readings: Map.unmodifiable(result));
  }

  String selectedText(Set<WearableMetric> selected) {
    if (selected.isEmpty || selected.any((m) => readings[m]?.hasData != true)) {
      throw const FormatException('Choose available readings to review.');
    }
    final text = [
      'My selected Health Connect records from this Android user’s phone',
      'Synced records, not live measurements or a diagnosis.',
      'Read/window end: ${to.toUtc().toIso8601String()}',
      'Window start: ${from.toUtc().toIso8601String()}',
      for (final metric in WearableMetric.values.where(selected.contains))
        '${metric.label}\n${readings[metric]!.describe()}',
      'Only these selected readings are included. Device/source accuracy is not verified. '
          'How I feel and any condition need their own context; these records do not establish either.',
    ].join('\n\n');
    if (text.length > 12000) {
      throw const FormatException('Choose fewer readings.');
    }
    return text;
  }
}
