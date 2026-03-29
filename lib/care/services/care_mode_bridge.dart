import '../../after_storm/models/storm_event.dart';

/// Bridge so AfterStormService can fan events into Care Mode.
///
/// Replace the TODO sections with your actual Care Mode / crisis map logic.
class CareModeBridge {
  CareModeBridge._internal();
  static final CareModeBridge instance = CareModeBridge._internal();

  void logStormEvent(StormEvent event) {
    // Wire this into your real Care Mode / crisis tracking.
    // Example implementation:
    // CareModeService.instance.recordStorm(
    //   id: event.id,
    //   when: event.timestamp,
    //   intensity: event.intensity,
    //   feeling: event.primaryFeeling,
    //   safetyRisk: event.safetyRisk,
    //   note: event.shortSummary,
    // );
  }
}
