/// Small ports (interfaces) so this module can compile without forcing
/// a hard dependency on your concrete MemoryGraph / Guardrails implementations.

abstract class MemoryGraphPort {
  /// Returns a compact signal map, e.g. {"mood":"stressed","energy":0.4,"topIntents":[...]}.
  Future<Map<String, dynamic>> getRecentSignals({Duration window = const Duration(days: 7)});

  /// Log an event for outcome learning.
  Future<void> logEvent(String type, Map<String, dynamic> payload);
}

abstract class GuardrailsPort {
  /// Return a sanitized / approved payload, or null to block it.
  Future<Map<String, dynamic>?> approveContent(Map<String, dynamic> draft);
}
