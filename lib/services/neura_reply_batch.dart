/// Groups text deltas for one scheduled UI update without changing their order.
/// The chat screen schedules at the next frame; tests can supply a manual clock.
class NeuraReplyBatch {
  NeuraReplyBatch({required this.schedule, required this.onFlush});

  final void Function(void Function()) schedule;
  final void Function(String delta, int count) onFlush;
  final _pending = StringBuffer();
  int _count = 0;
  int _generation = 0;
  bool _scheduled = false;
  bool _disposed = false;

  void add(String delta) {
    if (_disposed) return;
    _pending.write(delta);
    _count++;
    if (_scheduled) return;
    _scheduled = true;
    final generation = ++_generation;
    schedule(() {
      if (!_disposed && generation == _generation) flush();
    });
  }

  /// Flush before saving a completed reply or retaining an interrupted reply.
  void flush() {
    if (_disposed) return;
    _generation++;
    _scheduled = false;
    if (_count == 0) return;
    final delta = _pending.toString();
    final count = _count;
    _pending.clear();
    _count = 0;
    onFlush(delta, count);
  }

  /// Mode changes and disposal discard pending callbacks and retained text.
  void dispose() {
    _disposed = true;
    _generation++;
    _scheduled = false;
    _pending.clear();
    _count = 0;
  }
}
