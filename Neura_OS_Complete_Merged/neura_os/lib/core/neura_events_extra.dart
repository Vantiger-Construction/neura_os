// lib/core/neura_events_extra.dart
//
// Add-on events for mouth/viseme animation.
// Safe to include even if you don't use the viseme layer.

import 'neura_events.dart';

/// A lightweight viseme set (mouth shapes) for "looks alive" animation.
/// You can map these to your Rive state machine however you want.
enum NeuraViseme {
  rest,
  AI,
  E,
  I,
  O,
  U,
  WQ,
  FV,
  L,
  MBP,
  CHJSH,
  TH,
  KG,
  R,
  SZN,
  // Feel free to extend; missing mappings are ignored.
}

class NeuraVisemeEvent extends NeuraEvent {
  final NeuraViseme viseme;
  const NeuraVisemeEvent(this.viseme);

  @override
  String toString() => 'NeuraVisemeEvent($viseme)';
}

class NeuraMouthOpenEvent extends NeuraEvent {
  /// 0..1
  final double open;
  const NeuraMouthOpenEvent(this.open);

  @override
  String toString() => 'NeuraMouthOpenEvent(open=$open)';
}
