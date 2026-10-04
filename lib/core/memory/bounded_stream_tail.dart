import 'dart:collection';

/// Retains only the last [limit] matching items, in their original order.
/// Stops without returning stale data when the caller's generation changes.
Future<List<T>> boundedStreamTail<T>(
  Stream<T> source, {
  required int limit,
  bool Function(T)? matches,
  bool Function()? isCurrent,
}) async {
  if (limit <= 0 || (isCurrent != null && !isCurrent())) return <T>[];
  final tail = ListQueue<T>();
  await for (final item in source) {
    if (isCurrent != null && !isCurrent()) return <T>[];
    if (matches != null && !matches(item)) continue;
    if (tail.length == limit) tail.removeFirst();
    tail.addLast(item);
  }
  if (isCurrent != null && !isCurrent()) return <T>[];
  return tail.toList();
}
