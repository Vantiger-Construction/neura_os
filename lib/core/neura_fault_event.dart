import 'package:flutter/foundation.dart';

@immutable
class NeuraFaultEvent {
  final String message;
  final String? stack;
  final String source; // e.g. "FlutterError", "PlatformDispatcher"
  final DateTime atUtc;

  NeuraFaultEvent({
    required this.message,
    required this.source,
    this.stack,
    DateTime? atUtc,
  }) : atUtc = atUtc ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'type': 'NeuraFaultEvent',
        'message': message,
        'stack': stack,
        'source': source,
        'atUtc': atUtc.toIso8601String(),
      };
}
