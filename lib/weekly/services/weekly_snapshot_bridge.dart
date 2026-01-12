import '../../after_storm/models/storm_event.dart';

/// Bridge so AfterStormService can talk to your real Weekly Snapshot system
/// without knowing its internal classes.
///
/// Replace the TODO sections with your actual WeeklySnapshotService calls.
class WeeklySnapshotBridge {
  WeeklySnapshotBridge._internal();
  static final WeeklySnapshotBridge instance =
      WeeklySnapshotBridge._internal();

  Future<void> logStormEvent(StormEvent event) async {
    // TODO: wire this into your real Weekly Snapshot / Life Summary logic.
    // Example idea:
    // WeeklySnapshotService.instance.logStorm(
    //   date: event.timestamp,
    //   intensity: event.intensity,
    //   feeling: event.primaryFeeling,
    // );
  }
}
