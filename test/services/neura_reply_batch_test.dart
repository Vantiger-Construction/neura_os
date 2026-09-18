import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/neura_reply_batch.dart';

void main() {
  test('a burst schedules one update and preserves every delta in order', () {
    final scheduled = <void Function()>[];
    final delivered = <String>[];
    final counts = <int>[];
    final batch = NeuraReplyBatch(
      schedule: scheduled.add,
      onFlush: (delta, count) {
        delivered.add(delta);
        counts.add(count);
      },
    );
    final deltas = List.generate(1000, (index) => '$index ');
    for (final delta in deltas) {
      batch.add(delta);
    }
    expect(scheduled, hasLength(1));
    expect(delivered, isEmpty);
    scheduled.removeAt(0)();
    expect(delivered, [deltas.join()]);
    expect(counts, [1000]);
  });

  test('terminal flush preserves the tail without replaying stale callbacks',
      () {
    final scheduled = <void Function()>[];
    final delivered = <String>[];
    final batch = NeuraReplyBatch(
      schedule: scheduled.add,
      onFlush: (delta, _) => delivered.add(delta),
    );
    batch.add('First');
    batch.flush();
    batch.add(' second');
    scheduled.removeAt(0)(); // The callback superseded by the manual flush.
    expect(delivered, ['First']);
    scheduled.removeAt(0)();
    batch.flush();
    expect(delivered, ['First', ' second']);
  });

  test('empty provider deltas retain the sequence count without adding text',
      () {
    final scheduled = <void Function()>[];
    final batch = NeuraReplyBatch(
      schedule: scheduled.add,
      onFlush: (delta, count) {
        expect(delta, 'Hello');
        expect(count, 3);
      },
    );
    batch.add('');
    batch.add('Hello');
    batch.add('');
    expect(scheduled, hasLength(1));
    scheduled.single();
  });

  test('mode change or disposal discards pending text and future callbacks',
      () {
    final scheduled = <void Function()>[];
    final delivered = <String>[];
    final batch = NeuraReplyBatch(
      schedule: scheduled.add,
      onFlush: (delta, _) => delivered.add(delta),
    );
    batch.add('Do not display after disposal');
    batch.dispose();
    batch.add('nor this');
    batch.flush();
    scheduled.single();
    expect(delivered, isEmpty);
    expect(scheduled, hasLength(1));
  });

  test('interruption can retain the partial reply exactly once', () {
    final scheduled = <void Function()>[];
    final delivered = <String>[];
    final batch = NeuraReplyBatch(
      schedule: scheduled.add,
      onFlush: (delta, _) => delivered.add(delta),
    );
    batch.add('Partial ');
    batch.add('reply');
    batch.flush();
    batch.dispose();
    for (final callback in scheduled) {
      callback();
    }
    expect(delivered, ['Partial reply']);
  });
}
