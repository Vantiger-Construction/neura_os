# Neura Mood Widget — iOS setup (manual, required)

`NeuraMoodWidget.swift` in this folder is an **unbuilt scaffold**. It was
written without access to Xcode or a Mac, so it could not be added to the
project the normal way (Xcode manages Widget Extension targets inside
`Runner.xcodeproj/project.pbxproj`, a format that is unsafe to hand-edit —
a mistake there can break the entire iOS build for everyone). Someone with
Xcode needs to do the following once:

1. **Add the Widget Extension target.**
   Xcode → File → New → Target → iOS → *Widget Extension*. Name it
   `NeuraMoodWidget`. When prompted, do **not** include a Live Activity or
   configuration intent — this is a static timeline widget.

2. **Replace the generated Swift file** with `NeuraMoodWidget.swift` from
   this folder (drag it into the new target, or paste its contents into the
   file Xcode generated).

3. **Add an App Group capability** to both the `Runner` target and the new
   `NeuraMoodWidget` target (Signing & Capabilities → + Capability → App
   Groups), using the same group id on both — for example
   `group.com.neurocompanion.neuroCompanion`. This must match:
   - the `appGroupId` constant at the top of `NeuraMoodWidget.swift`, and
   - the id passed to `HomeWidget.setAppGroupId(...)` from Dart (see step 4).

4. **Call `HomeWidget.setAppGroupId` once at app startup, iOS only** —
   e.g. in `HomeWidgetBridge`'s constructor or `refresh()`:
   ```dart
   if (Platform.isIOS) {
     await HomeWidget.setAppGroupId('group.com.neurocompanion.neuroCompanion');
   }
   ```
   This was **not** added to `home_widget_bridge.dart` yet, since the group
   id doesn't exist until step 3 is done — add it as part of this setup, not
   before.

5. **Build once on a device or simulator**, add the widget to a home screen,
   and confirm it updates after a mood check-in and reflects Safe Mode by
   toggling it in Diagnostics.

6. **Optional follow-up, not required for a first ship**: `widgetURL` in
   `NeuraMoodWidget.swift` currently points at a placeholder
   `neuraos://widget/mood` scheme that isn't registered or handled by the
   app yet. Tapping the widget will open the app, but not deep-link to a
   specific screen, until that scheme is registered (`Info.plist` →
   `CFBundleURLTypes`) and handled in the app's routing.

Nothing above touches `project.pbxproj`, `Info.plist`, or any entitlements
file directly from this drafting session — those all require Xcode's own
UI to edit safely.
