import 'dart:async';

/// Lightweight cooperative cancellation token for streamed LLM generations.
///
/// This deliberately uses only Dart core libraries. The network client checks
/// the token between chunks and retry delays, and callers can also stop the
/// underlying HTTP client when cancellation is observed.
class NeuraGenerationCancel {
  final String generationId;
  bool _cancelled = false;
  final Completer<void> _cancelledCompleter = Completer<void>();

  NeuraGenerationCancel(this.generationId);

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _cancelledCompleter.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (!_cancelledCompleter.isCompleted) {
      _cancelledCompleter.complete();
    }
  }

  void throwIfCancelled() {
    if (_cancelled) {
      throw NeuraGenerationCancelled(generationId);
    }
  }

  /// A cancellation-aware delay used for exponential backoff.
  Future<void> delay(Duration duration) async {
    if (duration <= Duration.zero) {
      throwIfCancelled();
      return;
    }
    await Future.any<void>([
      Future<void>.delayed(duration),
      whenCancelled,
    ]);
    throwIfCancelled();
  }
}

class NeuraGenerationCancelled implements Exception {
  final String generationId;
  const NeuraGenerationCancelled(this.generationId);

  @override
  String toString() => 'NeuraGenerationCancelled($generationId)';
}
