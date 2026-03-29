/// Wearable/health data integration point.
///
/// This module defines the interface for ingesting health data
/// (steps, heart rate, sleep) from platform health APIs.
/// Actual platform integration requires `health` or `wearable_communicator` packages.
class HealthSnapshot {
  final int? steps;
  final int? heartRate;
  final double? sleepHours;
  final DateTime timestamp;

  const HealthSnapshot({
    this.steps,
    this.heartRate,
    this.sleepHours,
    required this.timestamp,
  });
}

class WearableHealthService {
  WearableHealthService._();
  static final instance = WearableHealthService._();

  /// Returns the most recent health snapshot.
  /// Override with real platform health API calls.
  Future<HealthSnapshot> latestSnapshot() async {
    // No wearable connected — return empty snapshot.
    return HealthSnapshot(timestamp: DateTime.now());
  }

  /// True once a wearable data source has been configured.
  bool get isConnected => false;
}
