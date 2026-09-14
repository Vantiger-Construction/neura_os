import 'dart:async';

import 'package:home_widget/home_widget.dart';

import '../../modules/mood/mood_store.dart';
import '../../reliability/safe_boot.dart';
import 'neura_widget_snapshot.dart';

/// Mirrors bounded app state onto the OS home-screen widget.
///
/// This is a best-effort, one-way mirror: it never reads anything back from
/// the widget to make a decision, and a plugin failure (including on every
/// platform without a native widget implementation, e.g. this app's desktop
/// targets) must never affect the rest of the app.
class HomeWidgetBridge {
  HomeWidgetBridge._() {
    SafeBoot.instance.safeMode.addListener(_onSafeModeChanged);
  }

  static final HomeWidgetBridge instance = HomeWidgetBridge._();

  static const androidProviderName = 'NeuraMoodWidgetProvider';
  static const iOSWidgetName = 'NeuraMoodWidget';

  String? _approvedNudgeTitle;

  /// Mirrors the title of a suggestion the dashboard has *already* decided
  /// to show in-app (post Autonomy Kernel / guardrail evaluation). Pass
  /// `null` once that suggestion is dismissed, acted on, or expires, so the
  /// widget never shows a stale nudge.
  void mirrorApprovedNudge(String? title) {
    _approvedNudgeTitle = title;
    unawaited(refresh());
  }

  void _onSafeModeChanged() => unawaited(refresh());

  /// Recomputes the snapshot from current state and pushes it to the OS
  /// widget. Safe to call as often as needed; every failure is swallowed.
  Future<void> refresh() async {
    try {
      final safeMode = SafeBoot.instance.safeMode.value;
      final lastMood = safeMode ? null : await MoodStore.instance.latest();
      final snapshot = buildNeuraWidgetSnapshot(
        safeMode: safeMode,
        now: DateTime.now(),
        lastMoodValue: lastMood?.mood0to10,
        lastMoodAt: lastMood?.timestamp,
        approvedNudgeTitle: _approvedNudgeTitle,
      );
      for (final entry in snapshot.toWidgetData().entries) {
        await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
      }
      await HomeWidget.updateWidget(
        androidName: androidProviderName,
        iOSName: iOSWidgetName,
      );
    } catch (_) {
      // No native widget on this platform, or the plugin call failed. The
      // widget is a mirror; the app must keep working regardless.
    }
  }
}
