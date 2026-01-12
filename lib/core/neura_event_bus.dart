import 'dart:async';

import 'neura_events.dart';

/// NeuraEventBus
///
/// A tiny, dependency-free event bus that supports:
/// - `NeuraEventBus.I.emit(event)`
/// - `NeuraEventBus.I.stream` (broadcast) for typed systems like AvatarOrchestrator
/// - `NeuraEventBus.I.on<T>((e) { ... })` which returns an unsubscribe function
/// - Back-compat: `onAny((Object e) { ... })` like the original shim
///
/// Notes:
/// - Emits are best-effort: listener exceptions are swallowed.
/// - The bus intentionally accepts **any** Object. Downstream listeners can filter.
class NeuraEventBus {
  NeuraEventBus._();

  static final NeuraEventBus I = NeuraEventBus._();

  final StreamController<Object> _controller = StreamController<Object>.broadcast();
  final List<void Function(Object)> _anyListeners = <void Function(Object)>[];

  /// Broadcast stream of all events.
  Stream<Object> get rawStream => _controller.stream;

  /// Broadcast stream filtered to a specific event type.
  Stream<T> streamOf<T>() => _controller.stream.where((e) => e is T).cast<T>();

  /// Convenience: stream of NeuraEvents.
  /// AvatarOrchestrator uses this.
  Stream<NeuraEvent> get stream => streamOf<NeuraEvent>();

  /// Emit an event to all subscribers.
  void emit(Object event) {
    // Notify legacy listeners first (they existed in the shim).
    if (_anyListeners.isNotEmpty) {
      for (final l in List<void Function(Object)>.from(_anyListeners)) {
        try {
          l(event);
        } catch (_) {
          // ignore
        }
      }
    }

    // Then stream subscribers.
    if (!_controller.isClosed) {
      try {
        _controller.add(event);
      } catch (_) {
        // ignore
      }
    }
  }

  /// Back-compat API from the original shim.
  void onAny(void Function(Object) listener) => _anyListeners.add(listener);
  void offAny(void Function(Object) listener) => _anyListeners.remove(listener);

  /// Typed subscription helper.
  /// Returns an unsubscribe function.
  void Function() on<T>(void Function(T event) listener) {
    final sub = streamOf<T>().listen(
      (e) {
        try {
          listener(e);
        } catch (_) {
          // ignore
        }
      },
    );
    return () => sub.cancel();
  }

  Future<void> dispose() async {
    _anyListeners.clear();
    await _controller.close();
  }
}
