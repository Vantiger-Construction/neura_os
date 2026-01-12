// lib/avatar/avatar_orchestrator_viseme_ext.dart
//
// Adds viseme/mouth handling to the AvatarOrchestrator without breaking older code.
// Import this file in the same place you create/start the orchestrator.

import '../core/neura_event_bus.dart';
import '../core/neura_events_extra.dart';
import 'avatar_controller.dart';
import 'avatar_controller_viseme_ext.dart';

class AvatarVisemeWiring {
  final AvatarController controller;
  final NeuraEventBus bus;

  void Function()? _unsubViseme;
  void Function()? _unsubMouth;

  AvatarVisemeWiring({required this.controller, required this.bus});

  void start() {
    _unsubViseme = bus.on<NeuraVisemeEvent>((e) {
      controller.setVisemeIndex(e.viseme.index);
    });
    _unsubMouth = bus.on<NeuraMouthOpenEvent>((e) {
      controller.setMouthOpen(e.open);
    });
  }

  void stop() {
    _unsubViseme?.call();
    _unsubMouth?.call();
    _unsubViseme = null;
    _unsubMouth = null;
  }
}
