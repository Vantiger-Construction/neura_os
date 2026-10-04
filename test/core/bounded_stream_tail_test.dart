import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/core/memory/bounded_stream_tail.dart';

void main() {
  test('keeps the last matching items in file order', () async {
    expect(
      await boundedStreamTail(
        Stream.fromIterable([1, 2, 3, 4, 5, 6]),
        limit: 2,
        matches: (int n) => n.isOdd,
      ),
      [3, 5],
    );
  });
  test(
    'recent tail counts blank and corrupt records before decoding',
    () async {
      expect(
        await boundedStreamTail(
          Stream.fromIterable(['valid', '', 'corrupt']),
          limit: 2,
        ),
        ['', 'corrupt'],
      );
    },
  );
  test('nonpositive limits do not subscribe', () async {
    final source = Stream<int>.multi((_) => throw StateError('subscribed'));
    expect(await boundedStreamTail(source, limit: 0), isEmpty);
    expect(await boundedStreamTail(source, limit: -1), isEmpty);
  });
  test('empty and short streams retain their original results', () async {
    expect(
      await boundedStreamTail(const Stream<int>.empty(), limit: 3),
      isEmpty,
    );
    expect(await boundedStreamTail(Stream.fromIterable([1, 2]), limit: 3), [
      1,
      2,
    ]);
  });
  test(
    'generation invalidation cancels reading and returns no stale items',
    () async {
      var current = true;
      var consumed = 0;
      Stream<int> source() async* {
        for (var i = 0; i < 100; i++) {
          consumed++;
          if (i == 3) current = false;
          yield i;
        }
      }

      expect(
        await boundedStreamTail(source(), limit: 2, isCurrent: () => current),
        isEmpty,
      );
      expect(consumed, 4);
    },
  );
  test('large histories match the previous tail semantics', () async {
    final result = await boundedStreamTail(
      Stream.fromIterable(Iterable<int>.generate(100000)),
      limit: 25,
      matches: (int n) => n % 3 == 0,
    );
    final expected =
        Iterable<int>.generate(100000).where((n) => n % 3 == 0).toList();
    expect(result, expected.sublist(expected.length - 25));
  });
  test(
    'stream errors propagate rather than silently truncating history',
    () async {
      expect(
        boundedStreamTail(
          Stream<int>.error(StateError('read failed')),
          limit: 2,
        ),
        throwsStateError,
      );
    },
  );
}
