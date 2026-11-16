# Wearable body awareness

This change adds an explicitly opened, read-only Android Health Connect screen
to Care Mode and Care Loop. It is a first connection for understanding a client's
recorded activity and their own description of how their body feels. It does not
infer a medical condition, diagnose illness, monitor emergencies, or run a model.

## Client flow

1. Use the client's own Android phone/user profile. Pair the wearable with its
   supported companion app and enable that app's Health Connect sharing using
   its own controls. A name entered into Neura cannot switch record ownership.
2. Open **Care Mode → Wearable body awareness** (also available in Care Loop).
   Opening the screen performs no permission query or health-data read.
3. Choose **Check connection and permissions**. Select the types to read. All
   selections begin off, independently of existing OS grants.
4. If needed, choose **Grant selected Android permissions**. Granting does not
   start a read. The system screen may background Neura and clear the temporary
   selection. Select again after returning.
5. Choose **Read selected data (last 24 hours)**. Review each returned value,
   timestamp, source app and recording method. Missing records or denied access
   are displayed explicitly; neither becomes a zero or a healthy finding.
6. Optionally write **How does your body feel?** This note is separate from
   sensor records, stays in the temporary screen, and is excluded from the
   reviewed text unless **Include my body note** is enabled.
7. Select individual available readings for the report, choose **Review selected
   readings for copying**, inspect the exact text, and attest that these are the
   client's own records. This approval expires after two minutes, is consumed by
   a copy attempt, and is invalidated by edits, selection changes or leaving.
8. **Copy reviewed readings** checks Personal Constitution external-message
   settings and current Android grants before dispatching a single clipboard
   operation. Nothing is automatically sent to a clinic, a model, chat, a
   journal or companion memory. The client may paste the reviewed text into
   Neura chat or a separately reviewed clinic report. Any cloud request still
   requires the existing exact-request approval.

Copying exposes the selected text to the system clipboard, other apps and any
enabled clipboard sync. Already-copied text cannot be retracted by clearing the
screen. A failed clipboard call is an unconfirmed outcome; it is never retried
automatically.

## Connection and data limits

- This connector uses Android's framework Health Connect API on Android 14+
  (API 34+). It adds no third-party health dependency and keeps Neura's existing
  minimum Android SDK. Older Android, Windows and iOS display unavailable;
  they do not receive demo values. No wearable model has been physically tested.
- Compatible source apps must actually write the selected data into Health
  Connect. For a supported Galaxy Watch, the route is watch → Samsung Health
  on the phone → Health Connect → Neura. Sync timing and supported fields vary;
  these are synced records, not a live Bluetooth feed. Samsung Health and other
  source apps retain their own independent storage and sync policies.
- Heart rate is the most recent in-window sample found in a bounded set of up
  to 50 returned records and 5,000 inspected samples. The timestamp, source
  package and manual/automatic/active/unknown recording method are shown.
  Further pages or a sample cap set an explicit limited-set flag. This does not
  guarantee the latest sample in all of Health Connect.
- Steps use the native aggregate API for the 24-hour window, rather than adding
  raw records from multiple apps. Health Connect's aggregation and source
  priorities determine the total. Up to 32 source package IDs are displayed;
  an incomplete source list is flagged. Phone and wearable records may both
  contribute. No data and an actual aggregate of zero remain distinct.
- Sleep shows the latest completed session fully contained in the window,
  among up to 50 returned records. **Session span is not measured time asleep**
  and is not a sleep-quality score. The SDK supplies whole session objects;
  Neura does not access or export their title, notes or sleep stages.
- Requests cover exactly the preceding 24 hours using device time. Native reads
  have a ten-second deadline; Dart also enforces a twelve-second wait. Record
  pagination is not followed. The native permission request has a 90-second
  outcome deadline and never resumes a data read.
- Flutter accepts only the requested metric keys, bounded numeric values,
  source package IDs and timestamps in the requested window. Unexpected fields,
  malformed records, stale responses and unsupported versions fail closed,
  without a generated interpretation or replacement value.

## Permissions and cancellation

Only `READ_HEART_RATE`, `READ_STEPS` and `READ_SLEEP` are declared. There is no
health write/delete, background-read or extended-history permission. The native
reader is initialized lazily after a foreground action, so the optional health
service is not needed for ordinary Neura startup.

OS permissions are checked before each selected native metric and again before
returning data. A single owned request ID prevents an old cancellation from
cancelling a newer read. Native pause/disposal cancels the active operation,
suppresses late SDK callbacks and prevents remaining metrics from being read.
This invalidates the result; it cannot retract a query already submitted to
Android's service. Cancellation/failure also drops the accumulated native metric
maps. Clearing drops Neura's active references; it is not secure erasure of
copies in Android, the SDK, memory or an already-used clipboard.

Flutter synchronously invalidates the screen on navigation cover, including a
cover/pop in the same frame, Stop, background/inactive, disposal, Safe Mode or
recovery. It clears readings, note, selection and approval, and ignores pending
read or permission-check completions. Nothing resumes automatically. Safe Mode
and recovery block reads and copying. OS permission management remains usable.

**Manage or revoke Android permissions** clears the temporary view and opens
Android's Health Connect app-permission settings. Opening settings does not
prove a grant was revoked. Returning starts nothing. **Stop and clear** does not
revoke Android permissions or delete records from Health Connect/source apps.

The manifest includes the required permission-rationale activity and Android
permission-usage alias. That exported activity is static text and cannot read
records. Before public distribution, independently validate permission behavior,
the public privacy policy and the applicable app-store Health Apps/Health
Connect declarations against the final shipped implementation.

## Validation and remaining acceptance

Synthetic fixtures cover strict payload validation, selected-only reporting,
missing data versus zero, unsupported platforms, permission grant without a
read, per-type requests, approval expiry/clock rollback, changed text and stale
callbacks, OS permission revocation, Constitution denial, background, Safe Mode,
recovery, same-frame route cover/pop, Stop, disposal and clipboard failure.

Record actual source/build evidence in the PR. Automated tests and a compiled
APK do not establish physical-device acceptance. No client records, real watch
data or credentials are used in tests. No device is installed over, reset or
cleared by this work.

Before enabling this for a client, use synthetic/test-device health data to:

- Confirm the actual watch/ring model and companion app support the three
  selected Health Connect types and that Neura reads the intended Android user.
- Compare the returned window, sources, step aggregate, heart-rate timestamp and
  sleep-session boundaries with Health Connect's records. Verify delayed, manual,
  absent and multiple-source inputs; do not interpret a gap as healthy.
- Test partial grants, denial, OS revocation, permission-dialog backgrounding,
  read interruption, Safe Mode, recovery, rapid navigation, restart and disposal.
  Confirm no hidden read or automatic restart after any interruption.
- Confirm temporary UI clearing, selected-only copy, body-note exclusion, exact
  renewed approval and independent clinic/cloud approvals on the final combined
  app. The clinic-report work in PR #212 is separate and is not merged here.
- Check startup on Android 24–33 without loading the API-34 service and verify
  normal startup on the Samsung SM-S366V Android 16 target. Existing Android
  startup/installation acceptance is not resolved by adding this connector.

## Primary references

- [Android: read Health Connect data](https://developer.android.com/health-and-fitness/health-connect/read-data)
- [Android: aggregate data and source priorities](https://developer.android.com/health-and-fitness/health-connect/aggregate-data)
- [Android: framework HealthConnectManager (API 34)](https://developer.android.com/reference/android/health/connect/HealthConnectManager)
- [Android: permission rationale and setup](https://developer.android.com/health-and-fitness/health-connect/get-started)
- [Android: Android 13 to 14 permission migration](https://developer.android.com/health-and-fitness/health-connect/migration/android-13-to-14)
- [Samsung: Health Connect FAQ and supported records](https://developer.samsung.com/health/health-connect-faq.html)
- [Samsung: accessing Health data through Health Connect](https://developer.samsung.com/health/blog/en/accessing-samsung-health-data-through-health-connect)
