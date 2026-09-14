/// Bounded, display-only data for the home-screen glanceable widget.
///
/// Deliberately holds nothing the widget shouldn't render as-is: a numeric
/// mood score and a relative age label, plus the title of a suggestion that
/// Neura's own attention/consent policy has *already* approved for in-app
/// display. Nothing here is computed independently of that existing
/// decision -- the widget mirrors state, it never originates one.
class NeuraWidgetSnapshot {
  const NeuraWidgetSnapshot({
    required this.safeMode,
    this.moodValue,
    this.moodAgeLabel,
    this.nudgeTitle,
  });

  /// Safe Mode blanks every field below to a neutral state rather than
  /// showing stale personal data while startup safety checks are active.
  const NeuraWidgetSnapshot.blank() : this(safeMode: true);

  final bool safeMode;
  final int? moodValue;
  final String? moodAgeLabel;
  final String? nudgeTitle;

  static const _keySafeMode = 'neura_widget_safe_mode';
  static const _keyMoodValue = 'neura_widget_mood_value';
  static const _keyMoodAge = 'neura_widget_mood_age';
  static const _keyNudgeTitle = 'neura_widget_nudge_title';

  /// String-keyed, string-valued payload matching what the native widget
  /// code (Android RemoteViews / iOS WidgetKit) reads back out.
  Map<String, String> toWidgetData() => {
        _keySafeMode: safeMode ? '1' : '0',
        _keyMoodValue: moodValue?.toString() ?? '',
        _keyMoodAge: moodAgeLabel ?? '',
        _keyNudgeTitle: nudgeTitle ?? '',
      };
}

/// Builds the widget-facing snapshot from already-loaded state. Kept as a
/// pure function (no store/plugin access) so the "what's safe to show"
/// decision can be unit tested without a platform channel.
NeuraWidgetSnapshot buildNeuraWidgetSnapshot({
  required bool safeMode,
  required DateTime now,
  int? lastMoodValue,
  DateTime? lastMoodAt,
  String? approvedNudgeTitle,
}) {
  if (safeMode) return const NeuraWidgetSnapshot.blank();
  return NeuraWidgetSnapshot(
    safeMode: false,
    moodValue: lastMoodValue,
    moodAgeLabel: lastMoodAt == null
        ? null
        : relativeAgeLabel(now: now, then: lastMoodAt),
    nudgeTitle: approvedNudgeTitle,
  );
}

/// A short, human-readable relative age (e.g. "5m ago", "3h ago", "2d ago").
/// A [then] in the future (clock skew) is treated as "just now" rather than
/// showing a negative duration.
String relativeAgeLabel({required DateTime now, required DateTime then}) {
  final diff = now.difference(then);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
