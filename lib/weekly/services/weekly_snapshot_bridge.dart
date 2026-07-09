import '../../after_storm/models/storm_event.dart';
import '../../after_storm/services/after_storm_service.dart';

/// Bridge so external modules can log storm events into the weekly snapshot
/// system without importing AfterStormService directly.
class WeeklySnapshotBridge {
  WeeklySnapshotBridge._internal();
  static final WeeklySnapshotBridge instance = WeeklySnapshotBridge._internal();

  /// Logs [event] via AfterStormService so it appears in the weekly snapshot.
  Future<void> logStormEvent(StormEvent event) async {
    await AfterStormService.instance.logEvent(event);
  }
}
