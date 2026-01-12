import 'dart:async';

import 'neura_events.dart';

/// Tiny typed event bus for Neura runtime signals.
/// No dependencies. One global instance is enough for most apps.
class NeuraEventBus {
  NeuraEventBus._();

  static final NeuraEventBus I = NeuraEventBus._();

  final StreamController<NeuraEvent> _controller = StreamController<NeuraEvent>.broadcast();

  Stream<NeuraEvent> get stream => _controller.stream;

  void emit(NeuraEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  void dispose() {
    _controller.close();
  }
}
