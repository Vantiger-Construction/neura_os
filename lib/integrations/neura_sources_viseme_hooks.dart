// lib/integrations/neura_sources_viseme_hooks.dart
//
// One-liners so any TTS/STT implementation can drive mouth/visemes without direct imports.

import '../core/neura_event_bus.dart';
import '../core/neura_events_extra.dart';

class NeuraVisemeHooks {
  static NeuraEventBus get _bus => NeuraEventBus.I;

  static void mouth(double open) => _bus.emit(NeuraMouthOpenEvent(open));
  static void viseme(NeuraViseme v) => _bus.emit(NeuraVisemeEvent(v));
  static void rest() {
    _bus.emit(const NeuraMouthOpenEvent(0.0));
    _bus.emit(const NeuraVisemeEvent(NeuraViseme.rest));
  }
}
