# Doctor and clinic contact

## Patient-controlled reports and reviewed handoff

The maintainer asked to resume clinic-contact work on November 15, 2026
(America/Chicago). This source change restores **Doctor & clinic** in Care Loop
and Care Mode and implements the patient-controlled report workflow below.
The earlier [hold/privacy audit](DOCTOR_CLINIC_CONTACT_AUDIT.md) remains a record
of its inspected revision. Enabling a setting alone never lifted that hold.
The maintainer explicitly approved the focused consent/lifecycle corrections on
November 17, 2026 (America/Chicago), for implementation and tests on a review
branch. Merging, persisted permission changes and repository settings were not
authorized. Current-head validation, independent review and physical acceptance
remain required before treating this workflow as release-ready.

The implemented scope is local report preparation, explicit copy/text-file
export and opening the patient's existing clinic portal or phone app. Direct
patient-to-clinic messaging, replies, AI participation in calls and appointment
booking still need an actual provider integration. No clinic, vendor or patient
has been selected, registered, subscribed to or contacted by this change.

## Workflow

1. Open **Care Loop / Care Mode → Doctor & clinic**. Each client fills in
   their full name, clinic/practice, optional named doctor, purpose, question,
   contact address/number and optional sharing instructions or limits. Check the contact against your clinic's own information. Syntax
   validation does not verify clinic ownership or patient identity.
2. Optionally press **Choose saved check-ins**. Only that gesture reads mood
   history. Choose up to ten of the latest thirty valid, non-future check-ins;
   none are selected automatically. Notes are excluded by default. Opting in
   includes at most 500 Unicode characters per selected note, with a visible
   shortening marker. Journals, chat and companion memory remain unopened.
3. Press **Prepare locally**. The deterministic report includes the chosen
   self-reports, your question, entered person/clinic, purpose and device time.
   It does not infer a diagnosis or invoke a model. Edit/remove any report text.
   Standard field selection and cut/copy/paste controls are disabled, including
   paste shortcuts; type edits and use the dedicated reviewed export buttons.
   This restriction has a usability/accessibility cost that needs device testing.
   The report is capped at 12,000 characters. In **Client permissions**, separately
   choose whether to allow copying/saving this report or opening the supplied
   doctor/clinic contact. Both start off. Each action still needs fresh review.
   Free-text instructions are literal report content; they do not grant a scope,
   enable a transport, or give access to clinic records.
4. **Review copy** shows the exact current text and clipboard consequences.
   **Copy reviewed report** copies only that text. Sign in, paste, review and
   send it in the clinic's portal yourself. Copying is not clinic delivery.
5. **Review text export** shows the exact text and explains that a UTF-8
   `neura-clinic-report.txt` file is unencrypted and may be synced by its chosen
   location. **Save reviewed text file** opens the system save dialog. The app
   does not automatically create temporary plaintext files. A cancelled picker
   is not a save receipt. A saved file is not a clinic message or a PDF.
6. **Review external handoff** shows the person, clinic, exact URL/number,
   edited report and what the OS receives. Contact attestation is required for
   this action. Approve **Open clinic portal** or **Open phone app** yourself.
   Only the URL or normalized number is passed; no report, patient name,
   clipboard text, authentication, query, fragment or headers are attached.
   A phone handler may immediately dial. Neura does not join the call.

Portal visits use the existing external browser, including its cookies, DNS
and redirects. The entered URL's path can itself reveal information, so use a
clinic-provided sign-in address without patient details. No browser automation,
provider inbox access, secret or OAuth token is added. Clinic messages are for
nonurgent communication; the workflow does not monitor or respond to emergencies.

## Consent, lifecycle and data boundaries

Copy, file export and OS handoff respect the existing Personal Constitution's
external-message permission. The screen does not enable it. If needed, the
patient changes **Adaptive Intent OS → Personal constitution → Allow external
messages**. Every action still requires a fresh review that expires after two
minutes. Approval binds the exact edited report and destination, is checked
again after asynchronous policy loading and is consumed before the OS call.
Edits and regenerating a report reset both client permission choices. Explicit
Personal Constitution saves/resets synchronously advance a policy revision and
revoke the open review and both choices before persistence can finish. Restoring
a policy value does not restore an old approval; the editable report is retained.
Changing either client choice revokes the
current review. The scopes are checked before/after policy loading and again
before dispatch; toggling one never grants the other. They are session-only,
with no saved default or automatic authorisation for a later client.

Edits, policy revocation, Stop, Safe Mode, recovery, background, route coverage
or disposal invalidate pending work. Clock rollback also invalidates a review.
A synchronous navigator observer catches a covering route even if immediately
popped. Only this workflow's own review may cover it without clearing details.
Retained form/review callbacks cannot revive a stopped operation.

The workflow creates no preference, encrypted-store, memory, log, telemetry or
contact-history record. Its own report, loaded check-ins and contact details
are cleared on any non-resumed lifecycle state or when another route covers
it. Returning never restores or sends a report. This is application-state
cleanup, not forensic erasure of RAM or operating-system state.

A dispatched clipboard write, system save or URL launch cannot be retracted.
An OS save may complete after backgrounding, closing or wiping Neura; the
explicitly exported file is outside app-managed memory and is not removed by
an app wipe. Clipboard data and files remain under the OS/destination's control.
The UI suppresses late success/error updates after revocation and never treats
an external app opening as delivery, a clinic reply or a booked appointment.
An exception is an unconfirmed outcome; there is no automatic resend/fallback.

## Validation and acceptance

Synthetic tests cover report selection, note exclusion, exact edited Unicode
exports, cancellation, policy changes, stale approvals, recovery, route
interleavings, background/stop and late completions. Existing destination and
OS-handoff regressions remain. No real patient data or clinic is used.

Current-head Windows and Android builds must be checked separately. Physical
Windows/Samsung save dialogs, clipboard, portal/phone handlers, accessibility,
clinic acceptance and actual delivery remain unverified until explicitly tested.
No patient authentication, hospital partnership, medical capability, compliance
certification or clinical benefit follows from these unit tests.

## Remaining integration: direct secure messages

Select the first supported clinic/portal before implementing a transport.
Verify its supported **patient-to-care-team messaging** interface and obtain
the necessary application registration and patient authorization. SMART on
FHIR specifies authorization; it does not by itself provide universal inbox
access. FHIR `CommunicationRequest` records a request and explicitly does not
represent actual communication. A successful resource write must not be shown
as a delivered or read clinic message.

The transport must bind the authenticated patient, verified care-team
recipient, endpoint, exact edited content, attachments, expiry and one-time
approval to one operation. Rust must enforce execution independently of model
output, retrieved text or Flutter button state. Invalidate on edits, patient
switch, revocation, Safe Mode, background and stop. No automatic memory export,
new recipients, cloud model access or treatment decisions. Existing local-only
health-content restrictions need an explicit, scoped sharing policy rather
than silently becoming a general cloud permission.

Use provider-supported idempotency and receipt reconciliation. A timeout is an
unknown outcome until reconciled; do not resend blindly. Show distinct draft,
submitted, accepted/delivered and clinician-response states using evidence the
provider actually supplies. Receive replies only within the patient's allowed
scope. Store any retained content encrypted under an authenticated owner's
key, with revoke, wipe, retention and export behavior. Named personality
preferences do not establish patient identity or record-access authority.

## Remaining integration: Neura speaking on live calls

Select a telephone provider and approved deployment before adding call audio.
The current local SAPI/Android speech paths do not bridge Neura into a phone
call. A voice service with bidirectional media is one possible integration;
it changes what leaves the device and needs its own explicit approval.

The user must review the verified clinic number, task, allowed facts and
questions, audio-processing destinations and cost limit. Require a foreground
user who can listen, take over or end the call. Introduce Neura as an AI
assistant acting with the person's permission; support the clinic's identity
checks and refusal to speak with an assistant. Do not impersonate a patient
or clinician, provide treatment instructions, make care decisions, or disclose
new facts beyond the approved brief. Further disclosures need fresh approval.
Recording is off; any future recording feature needs a separate consent flow.

The Rust owner must stop Neura's audio on stop, background, lock, loss of
ownership or Safe Mode, verify termination, and prevent late audio or automatic
redial. A human takeover needs a tested provider mechanism that stops AI audio
while preserving the person's conversation. Provider/webhook authenticity,
session binding, replay prevention, spending limits and secret storage must
be verified before real use. Windows and the Samsung SM-S366V need physical
call and lifecycle acceptance; mocked link launches do not establish this.

## Regression coverage

`test/care/clinic_contact_test.dart` exercises ordinary clinic report entry
points and uses synthetic people, reserved example domains and mocked OS links.
It retains destination restrictions, exact URL/number handoff without patient
payload, cancel, edited contact, policy changes, Safe Mode, inactivity, expiry,
platform failure, late completion, route disposal and narrow-screen coverage.

`test/care/clinic_report_test.dart` covers explicit history admission, selected
records and optional notes, a ten-record cap, exact edited Unicode copy/text
export, cancelled save, policy revocation, stale review/form callbacks, recovery,
late history/clipboard results and synchronous route-cover/pop interleavings.
These tests do not establish physical OS behavior or clinic delivery. The
`previewForTesting` constructor is now an alias for the same normal workflow,
not a feature switch; both entry points use normal construction.

## November 17 correction and synthetic acceptance

The production application now registers the clinic route observer used by its
preparation gate. Previously only the clinic test harnesses registered it, so
those tests could pass while the production editor remained disabled. The new
navigator-configuration contract tests obtain the actual app builder's observer
list and navigator key, substituting only a synthetic home and shell to avoid
starting live services. They exercise both care entry points and route coverage;
they do not claim that full application boot or a physical device was tested.

Additional regressions cover revoke-then-restore without navigation, permission
reset on regeneration and a new client session, changed contact/content, standard
editor clipboard paths, and delayed save success/cancellation/errors after Stop,
background, safety changes, disposal or policy revocation. Clipboard tests mock
the actual platform channel rather than observing only the dedicated exporter.
Full-wipe tests use the existing isolated fixture, including pending history,
review and already-dispatched save, an early backup-drain failure, retry and
repeated wipe while Safe Mode is already latched. A dispatched OS save remains
outside app-managed encrypted storage; these tests must not assert retraction.

Focused validation uses the branch-pinned Flutter 3.47.9 / Dart 3.13.7:

```sh
flutter test --no-pub --concurrency 2 --timeout 2m \
  test/care/clinic_contact_test.dart \
  test/care/clinic_report_test.dart \
  test/care/clinic_app_integration_test.dart \
  test/care/clinic_data_wipe_test.dart \
  test/constitution/neura_constitution_service_test.dart
```

The baseline audited was `308765ef0e6a078bfe731b9aa8a2d5fdbc427b53`.
New regression results, strict analysis and current-head package checks must be
recorded in the correction PR. The implementation host did not have the pinned
Flutter/Dart SDK; an attempted official SDK download returned HTTP 404. Local
source/whitespace checks do not substitute for executing Flutter tests in CI.

For a manual rehearsal, type only Alex Example, Example Clinic, Dr Taylor Example,
`https://clinic.example.invalid/login` and a question marked TEST ONLY. On an
installation with private data, leave **Choose saved check-ins** untouched. Use
injected synthetic check-ins in automated tests or a disposable data environment.
Prepare with both client scopes off, edit/regenerate, close/reopen and check that
no scope follows the earlier report. If the Personal Constitution blocks export,
record that result and leave the setting unchanged until separately authorized.

Cancel the external-handoff review on real devices; approve URL/phone operations
only against a mock launcher. Do not dial a fictional-looking number. Copy/save
only fictional text to an empty local editor or unsynced test folder; test picker
cancellation separately. Background or Stop may suppress Neura's late status while
an already-dispatched file still completes. Wipe tests belong only in disposable
synthetic fixtures, never against real encrypted memories. Record exact source
and package identity, platform, expected/observed outcome and PASS/FAIL/BLOCKED.
Windows and Samsung physical results remain separate from CI and packaging.

## Primary technical references

- [SMART App Launch authorization](https://hl7.org/fhir/smart-app-launch/app-launch.html)
- [FHIR R4 CommunicationRequest boundaries](https://www.hl7.org/fhir/R4/communicationrequest.html#scope)
- [Twilio bidirectional voice Media Streams](https://www.twilio.com/docs/voice/media-streams)

Twilio is a researched example, not a selected provider or a compliance claim.
Any applicable healthcare service agreements and deployment requirements must
be established for the chosen clinic and providers before handling live data.
