# Doctor and clinic contact

## Status: on hold; preparation and handoff unavailable

[PR #187](https://github.com/Vantiger-Construction/neura_os/pull/187) merged
on November 6, 2026 at 15:01:43 UTC even though its description retained the
maintainer's instruction to leave it open as a draft for later. The merge is
not evidence that the hold was lifted. The
[hold and privacy audit](DOCTOR_CLINIC_CONTACT_AUDIT.md) records the discrepancy
and the corrective access restriction.

The Doctor & clinic entry points have been removed from Care Loop and Care
Mode. Normal construction of `ClinicContactScreen` shows an on-hold notice
without mounting the form, reading policy, accepting health details or opening
an external application. Enabling the existing external-message permission
does not lift this hold. No new preference, runtime switch or build define
enables the feature. The retained implementation is reachable only through
an explicitly named, debug-only test constructor, annotated `visibleForTesting`;
that constructor also shows the hold notice in profile/release builds.
Restoring application access requires a separately reviewed source change and
an explicit maintainer decision. Existing sharing settings are not changed.

The requested destination is both secure written communication and live calls
in which Neura can speak with a person's own doctor or health clinic. These
channels require real integrations. The retained, deferred implementation
provides **local preparation and a reviewed handoff to the person's browser
or phone app**. It does not
implement direct sending, clinic replies, patient authentication or an AI phone
agent. No provider has been selected, subscribed to or contacted.

## Deferred workflow (synthetic regression tests only)

The following describes the preserved workflow exercised by tests; these are
not currently available application instructions.

1. Enter your name, doctor/clinic name, purpose and the details you want to
   discuss. Choose **Portal message** or **Phone call brief**.
2. Enter the clinic's HTTPS sign-in address or ordinary phone number. Check it
   using information from your clinic. Neura validates syntax, not ownership or
   your patient identity. Use a sign-in URL without query parameters, fragments
   or embedded credentials; phone extensions and dial commands are rejected.
3. Select **Prepare locally**. The deterministic template includes only what
   you entered and identifies Neura as an AI assistant. No model is invoked.
   No journals, mood entries, memories, saved contacts or other private stores
   are read. This first version is for contacting your own care team; it does
   not establish caregiver/proxy authority or authenticated multi-person profiles.
4. For a portal message, select and copy the draft yourself if desired. The
   UI warns that the system clipboard may be accessible to other apps or synced
   devices. Neura does not write to the clipboard automatically.
5. Select **Review external handoff**. The review names the person, clinic,
   exact destination, draft and what is passed to the external app. Confirm
   **Open clinic portal** or **Open phone app** to continue. Sign in and send the
   message yourself, or speak to the clinic yourself using the call brief.

The portal link contains no automatically attached patient name, message, notes,
headers or authentication. The browser makes a normal visit to the address you
entered, including its path. A manually entered path can itself contain sensitive
information; syntax validation does not prove clinic ownership or control DNS,
redirects, browser cookies or the browser's network disclosures.
The phone link contains only the normalized number. The phone app may
place a call immediately; a `tel:` link is not an audio connection for Neura.
An OS link handler may be unavailable on Windows or Android. The UI reports
handoff failure without claiming delivery, a clinic response or an appointment.

## Consent and temporary data

External handoff consults the existing Personal Constitution and is blocked by
default when external messages are disabled. This screen cannot change that
setting; it is in **Adaptive Intent OS → Personal constitution → Allow external
messages**. Even when permitted, every handoff requires a fresh two-minute review.
The permission is consumed before the platform call. There is no automatic
retry, alternate destination, fallback, scheduling or background contact.

Editing details invalidates the prepared draft and contact confirmation. Safe
Mode blocks handoff and clears temporary details. Pausing, hiding or detaching
the app clears the details and removes an open review. Transient inactivity
invalidates and dismisses a review. Resuming cannot restore its approval. The
screen owns its temporary controllers; closing it disposes them. There is no
new file, preferences key, backup, log entry or companion-memory record.
Removing the preparation route also dismisses its owned review dialog; it
must not leave the person's details visible over another screen.
This is application-state cleanup, not a guarantee of RAM zeroization or OS
screenshot/clipboard deletion. Data a person copies or enters in another app
is controlled by that app. The clinic draft is deliberately not restored after
the browser opens and Neura backgrounds.

Cancellation, background transitions and Safe Mode revoke approval before a
handoff is dispatched and suppress stale application callbacks. After a reviewed
link has already been passed to the OS, Neura cannot retract the browser visit,
close that application, stop a phone call or erase its data. These protections
must not be presented as cancellation of an external operation already started.

This feature does not diagnose, prescribe, recommend medication changes or
monitor emergencies. It passes along the person's own words and questions.
Urgent care must not depend on a portal message or on Neura noticing a problem.

## Future requirements on hold: direct secure messages

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

## Future requirements on hold: Neura speaking on live calls

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

## Verification

`test/care/clinic_contact_test.dart` uses synthetic people, reserved example
domains and mocked OS links. It covers local preparation, no preference writes,
destination restrictions, exact URL/number handoff without patient payload,
cancel, edited contact, policy changes, Safe Mode, background, inactivity,
expiry, failure, late completion and route disposal. It cannot
establish real delivery, clinician acceptance, physical audio or installation.

Hold regressions check the absence of entry points in both care screens, a
blocked directly constructed screen even with external-message permission,
and no automatic activation across background/resume or Safe Mode changes.
The deferred tests use `ClinicContactScreen.previewForTesting()` in debug test
execution. They retain all preparation and handoff safeguards, including late
platform completions after background, Safe Mode, clearing or disposal. They
do not enable a production route or authorize real patient communications.

## Primary technical references

- [SMART App Launch authorization](https://hl7.org/fhir/smart-app-launch/app-launch.html)
- [FHIR R4 CommunicationRequest boundaries](https://www.hl7.org/fhir/R4/communicationrequest.html#scope)
- [Twilio bidirectional voice Media Streams](https://www.twilio.com/docs/voice/media-streams)

Twilio is a researched example, not a selected provider or a compliance claim.
Any applicable healthcare service agreements and deployment requirements must
be established for the chosen clinic and providers before handling live data.
