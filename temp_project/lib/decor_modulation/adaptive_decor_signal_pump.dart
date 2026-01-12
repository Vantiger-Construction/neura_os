import 'dart:convert';
import 'package:flutter/services.dart';
import 'adaptive_decor_modulation_service.dart';

/// Example hook: call this from wherever you compute mood/time/intent.
/// Plug into your existing Persona/Mood engine.
class AdaptiveDecorSignalPump {
  AdaptiveDecorSignalPump._();
  static final AdaptiveDecorSignalPump instance = AdaptiveDecorSignalPump._();

  Future<void> init() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/room_decor_modulators.json');
      await AdaptiveDecorModulationService.instance.initFromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );
    } catch (_) {
      // Missing asset? keep defaults
    }
  }

  Future<void> tick({
    required String mood,
    required String timeOfDay,
    required String intent,
  }) async {
    await AdaptiveDecorModulationService.instance.update(
      mood: mood,
      timeOfDay: timeOfDay,
      intent: intent,
    );
  }
}
