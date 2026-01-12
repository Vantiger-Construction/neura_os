import '../../after_storm/models/storm_event.dart';

/// Bridge so AfterStormService can fan events into Care Mode.
///
/// Replace the TODO sections with your actual Care Mode / crisis map logic.
class CareModeBridge {
  CareModeBridge._internal();
  static final CareModeBridge instance = CareModeBridge._internal();

  Future<void> logStormEvent(StormEvent event) async {
    // TODO: wire this into your real Care Mode / crisis tracking.
    // Example idea:
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
