import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

/// Adaptive Decor Modulation
///
/// Sends high-level mood/time/intent signals to Unity so the world can
/// subtly adapt (lighting/material emission/etc) without scene reloads.
///
/// Safety:
/// - Interpolation on Unity side (no snapping).
/// - Rate-limited (minSecondsBetweenUpdates).
class AdaptiveDecorModulationService {
  AdaptiveDecorModulationService._();
  static final AdaptiveDecorModulationService instance = AdaptiveDecorModulationService._();

  static const MethodChannel _toUnity = MethodChannel('neura/unity');

  DateTime? _lastSent;
  double minSecondsBetweenUpdates = 1.5;

  Future<void> initFromJson(Map<String, dynamic> modulators) async {
    final defaults = modulators['defaults'];
    if (defaults is Map && defaults['minSecondsBetweenUpdates'] != null) {
      minSecondsBetweenUpdates = (defaults['minSecondsBetweenUpdates'] as num).toDouble();
    }
  }

  Future<void> update({
    required String mood,
    required String timeOfDay,
    required String intent,
  }) async {
    final now = DateTime.now();
    if (_lastSent != null) {
      final dt = now.difference(_lastSent!).inMilliseconds / 1000.0;
      if (dt < minSecondsBetweenUpdates) return;
    }
    _lastSent = now;

    final payload = <String, dynamic>{
      "type": "SET_DECOR_MODULATION",
      "mood": mood,
      "timeOfDay": timeOfDay,
      "intent": intent,
      "ts": now.toIso8601String(),
    };

    try {
      await _toUnity.invokeMethod('sendToUnity', jsonEncode(payload));
    } catch (_) {
      // Unity missing? No problem. Never block Flutter UX.
    }
  }
}
