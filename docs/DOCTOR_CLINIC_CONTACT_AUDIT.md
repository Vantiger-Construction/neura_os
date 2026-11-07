# Clinic-contact hold and privacy audit

Audit date: November 6, 2026 (America/Chicago).
Inspected default-branch revision:
[`a74330c25e79a07bf3d70724cc50f09c473aa1c2`](https://github.com/Vantiger-Construction/neura_os/tree/a74330c25e79a07bf3d70724cc50f09c473aa1c2).

## Decision and merge discrepancy

[PR #187](https://github.com/Vantiger-Construction/neura_os/pull/187) records
merge commit `3b3be4a5d846ed9a57206560a4005f0fc7aa502e` at
2026-11-06 15:01:43 UTC. At audit time its description still instructed that
the PR remain an open draft until the maintainer asked to proceed. GitHub's
review submissions list was empty. The merge therefore conflicts with the
recorded hold; no instruction lifting that hold was found in the inspected
discussion or available user context. This audit does not infer who authorized
or performed the merge from an automated account identity.

The default branch exposed the form from both Care Loop and Care Mode, even
though external handoff required a separate permission. A permission blocking
outgoing links does not enforce a hold on access to the preparation feature.
Three new hold regressions failed against that revision: the normal screen
accepted details, and both care screens exposed the clinic entry point.
The original 18 clinic regressions passed before the correction.

A separate privacy regression exposed another defect: programmatically removing
the preparation route left its root-navigator review dialog visible, including
the typed name, clinic and notes. Disposal already prevented that stale review
from launching a link, but did not remove its displayed details. The correction
dismisses only the owned review after unmount, before the next rendered frame,
without mutating a navigator while its route/overlay tree is locked.

## Privacy findings for the deferred implementation

| Boundary | Source and mocked-test finding | Practical limit |
| --- | --- | --- |
| Inputs and storage | Deterministic templates use the four typed fields and selected purpose/channel. The workflow does not read health records, journals, memory or saved contacts, and does not persist the draft. | Typed names are not authenticated patient identity. Controller disposal does not prove RAM zeroization or erase OS screenshots or clipboard data. |
| Destinations | HTTPS sign-in URLs reject credentials, query/fragment payloads, nonstandard ports, IP literals and local host syntax; phone links reject extensions, commands and pauses. | Syntax is not clinic ownership, DNS or redirect verification. A person-entered URL path may itself reveal information. |
| Review | Contact confirmation, loaded Personal Constitution permission and a fresh two-minute destination/content review are required. Edits invalidate the draft and confirmation. Policy is checked again immediately before dispatch. | A generic permission alone never authorizes a handoff. No new sharing setting is enabled by this correction. |
| Outgoing data | The external-app launch receives the reviewed URI with no draft fields or authentication headers attached. Phone handoff contains only the normalized number. | A browser makes a normal visit, with its own cookies and network behavior. A phone handler may immediately place a call. |
| Cancellation and expiry | Cancel, dismissed review and expiry do not dispatch a link. Approval is consumed before launch. No automatic retry or fallback exists. | Once dispatched to the OS, the visit or call cannot be recalled by Neura. |
| Background and inactivity | Inactivity revokes/dismisses review. Hidden, paused and detached states clear temporary details. Resuming does not restore approval. Epoch checks suppress stale completions. | Mocked lifecycle events do not establish physical Android/Windows behavior. Transient inactivity alone deliberately retains editable details. |
| Safe Mode and disposal | Safe Mode clears details and prevents a new handoff; disposal invalidates pending work. Late platform results cannot restore a cleared draft or success state. The correction also removes an orphaned review when its preparation route is removed. | These controls do not terminate an external app or phone call already opened by the OS. |
| Integration scope | There is no clinic transport, patient authentication, clinician reply channel, health-record ingestion or Neura call-audio bridge. No model or microphone is invoked by this workflow. | Mocked tests are development evidence, not clinical validation or healthcare integration readiness. |

## Focused correction

Remove the two clinic navigation entries and make normal `ClinicContactScreen`
construction display a hold notice without instantiating the preparation state.
Keep the implementation and synthetic regression coverage through a
`visibleForTesting` constructor guarded by `kDebugMode`; it cannot mount the
workflow in profile/release builds. There is no runtime preference, environment
define or application navigation path that releases this hold. No stored
sharing choices are changed. This preserves useful work while application
access and all future direct clinic integrations remain deferred.

The retained workflow also receives the focused review-dialog cleanup fix,
with a regression that removes the owning route while its review is open.

Update the workflow documentation to describe the merged-but-held status and
label the retained instructions as test-only. Record the correction in a
separate PR for independent review. Publication of that PR does not restrict
the default branch until it is merged, and does not change previously built
packages. Do not merge or release merely because local checks pass.

Validation uses the branch-pinned Flutter 3.47.9 / Dart 3.13.7, synthetic people,
reserved example domains and mocked external applications. The correction PR
records the final source tree, focused/full Flutter results and strict analysis.
Physical acceptance on Windows and the Samsung SM-S366V, actual OS handoff and
clinic acceptance remain unverified. Future access or integration needs an
explicit maintainer decision, independent review, scoped patient authorization
and the acceptance work described in [the implementation requirements](DOCTOR_CLINIC_CONTACT.md).
