import 'dart:async';

import 'neura_events.dart';

/// Tiny typed event bus for Neura runtime signals.
/// No dependencies. One global instance is enough for most apps.
class NeuraEventBus {
  NeuraEventBus._();

  static final NeuraEventBus I = NeuraEventBus._();

  final StreamController<NeuraEvent> _controller = StreamController<NeuraEvent>.broadcast();

  Stream<NeuraEvent> get stream => _controller.stream;

  /// Listen to events of a specific type.
  ///
  /// Returns an unsubscribe callback.
  void Function() on<T extends NeuraEvent>(void Function(T event) handler) {
    final sub = stream.where((e) => e is T).cast<T>().listen(handler);
    return () => sub.cancel();
  }

  void emit(NeuraEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  void dispose() {
    _controller.close();
  }
}
