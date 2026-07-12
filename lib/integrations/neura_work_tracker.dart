import 'dart:async';

/// A tiny ref-count tracker so overlapping jobs don't flicker.
///
/// Example:
///   final token = tracker.begin();
///   try { await work(); } finally { token.release(); }
class NeuraWorkTracker {
  NeuraWorkTracker({required void Function(bool) onActiveChanged})
      : _onActiveChanged = onActiveChanged;

  final void Function(bool) _onActiveChanged;

  int _count = 0;
  bool get isActive => _count > 0;

  /// Debounce end transitions slightly to prevent "blink" during chained Futures.
  final Duration settleDelay = const Duration(milliseconds: 120);
  Timer? _settle;

  NeuraWorkToken begin() {
    _settle?.cancel();
    _settle = null;

    _count++;
    if (_count == 1) _onActiveChanged(true);

    return NeuraWorkToken._(() {
      if (_count <= 0) return;
      _count--;
      if (_count == 0) {
        _settle?.cancel();
        _settle = Timer(settleDelay, () {
          // Still zero after settle? then emit false.
          if (_count == 0) _onActiveChanged(false);
        });
      }
    });
  }

  Future<T> track<T>(Future<T> future) {
    final token = begin();
    return future.whenComplete(token.release);
  }

  Future<T> trackFn<T>(Future<T> Function() fn) {
    final token = begin();
    try {
      final fut = fn();
      return fut.whenComplete(token.release);
    } catch (_) {
      token.release();
      rethrow;
    }
  }

  /// Track a Stream so "active" remains true until the stream completes or is cancelled.
  Stream<T> trackStream<T>(Stream<T> stream) {
    final token = begin();
    late final StreamSubscription<T> sub;
    final controller = StreamController<T>(
      onCancel: () async {
        try {
          await sub.cancel();
        } finally {
          token.release();
        }
      },
    );

    sub = stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: () {
        token.release();
        controller.close();
      },
      cancelOnError: false,
    );

    return controller.stream;
  }

  void dispose() {
    _settle?.cancel();
    _settle = null;
    _count = 0;
  }
}

class NeuraWorkToken {
  NeuraWorkToken._(this._release);

  final void Function() _release;
  bool _done = false;

  void release() {
    if (_done) return;
    _done = true;
    _release();
  }
}
