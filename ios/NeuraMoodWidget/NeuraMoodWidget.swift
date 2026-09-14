// UNVERIFIED SCAFFOLD -- not part of the buildable app yet.
//
// This file has never been compiled: it was authored on a machine without
// Xcode, as a starting point for the Widget Extension target described in
// SETUP.md in this folder. It will not build until that target exists and
// this file is added to it.
//
// Renders only the bounded, display-only data HomeWidgetBridge (Dart side,
// lib/os_shell/widgets_bridge/) already computed and saved to the shared App
// Group -- this widget makes no decisions of its own.

import SwiftUI
import WidgetKit

/// Must match HomeWidgetBridge.iOSWidgetName in the Dart bridge.
private let widgetKind = "NeuraMoodWidget"

/// Must match the App Group configured for both the main app and this
/// extension in Xcode (Signing & Capabilities > App Groups), and the id
/// passed to HomeWidget.setAppGroupId(...) from Dart. See SETUP.md.
private let appGroupId = "group.com.neurocompanion.neuroCompanion"

private struct NeuraMoodEntry: TimelineEntry {
    let date: Date
    let safeMode: Bool
    let moodValue: String
    let moodAge: String
    let nudgeTitle: String
}

private struct NeuraMoodProvider: TimelineProvider {
    func placeholder(in context: Context) -> NeuraMoodEntry {
        NeuraMoodEntry(
            date: Date(), safeMode: false, moodValue: "7", moodAge: "2h ago",
            nudgeTitle: "")
    }

    func getSnapshot(
        in context: Context, completion: @escaping (NeuraMoodEntry) -> Void
    ) {
        completion(currentEntry())
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<NeuraMoodEntry>) -> Void
    ) {
        // No periodic refresh: the app pushes a new entry via
        // HomeWidget.updateWidget() whenever state actually changes (mood
        // saved, an already-approved nudge shown/dismissed, Safe Mode
        // toggled), so a single-entry timeline is sufficient.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> NeuraMoodEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let safeMode = defaults?.string(forKey: "neura_widget_safe_mode") == "1"
        return NeuraMoodEntry(
            date: Date(),
            safeMode: safeMode,
            moodValue: defaults?.string(forKey: "neura_widget_mood_value") ?? "",
            moodAge: defaults?.string(forKey: "neura_widget_mood_age") ?? "",
            nudgeTitle: safeMode
                ? ""
                : (defaults?.string(forKey: "neura_widget_nudge_title") ?? "")
        )
    }
}

private struct NeuraMoodWidgetView: View {
    let entry: NeuraMoodEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(moodLine)
                .font(.headline)
            if !entry.nudgeTitle.isEmpty {
                Text(entry.nudgeTitle)
                    .font(.caption)
            }
            if entry.safeMode {
                Text("Safe Mode is active")
                    .font(.caption)
            }
        }
        .padding()
        // Opens the app on tap; deep-linking to a specific screen is a
        // possible follow-up once app-side URL routing supports it.
        .widgetURL(URL(string: "neuraos://widget/mood"))
    }

    private var moodLine: String {
        entry.moodValue.isEmpty
            ? "No check-in yet"
            : "Last check-in: \(entry.moodValue)/10 (\(entry.moodAge))"
    }
}

struct NeuraMoodWidget: Widget {
    let kind: String = widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NeuraMoodProvider()) { entry in
            NeuraMoodWidgetView(entry: entry)
        }
        .configurationDisplayName("Neura Mood")
        .description("Your latest mood check-in and any current gentle suggestion.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
