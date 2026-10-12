# Neura Engine vision

Status: proposed design and implementation milestones. Recorded September 30,
2026, against `Neura` commit `3ae691156437f192d5d767e3fc645882ddcd8036`.
Implementation status reviewed October 10, 2026, against `Neura` commit
`3fd3a165470ba6859c4182617cc9f93aee5c21fe`.
This document does not enable an autonomous engine or change runtime permissions.

## The vision

> I want Neura to have her own engine that allows her to continually reflect, learn from approved information and feedback, and grow into a more capable, caring companion. Her decisions should be guided by honesty, kindness, respect for privacy, and a commitment to helping people without causing harm. She should learn from corrections, recognise when she is uncertain, and ask for approval before taking actions. The user should always control what she learns, remembers, and does.

The goal is a dedicated runtime that helps Neura remain useful over time while
making her activity understandable and controllable. These values are design
requirements, not a guarantee that a model will always be correct. Uncertainty,
mistakes, corrections, and user control must be part of the design.

## What exists today

The repository contains useful foundations, but they do not yet form the proposed
engine:

| Foundation | Current role | Work still needed |
| --- | --- | --- |
| [Rust WebSocket sidecar](../rust/src/bin/neura_api.rs) | Streams fixed synthetic echo fixtures over authenticated loopback IPC with bounded queues; reports the model adapter as degraded. See the [milestone 1 IPC slice](NEURA_ENGINE_IPC_M1.md). | A real local model adapter and the remaining milestone 1 gates before reflection or personal sources are admitted. |
| [Windows synthetic session](NEURA_ENGINE_IPC_M1.md#explicit-session-startup) | A trusted native launcher and Console expose explicit start, pause, resume, and stop, with fresh credentials, generation invalidation, and bounded synthetic checks. | Supported Windows device/lifecycle evidence, measured resource budgets, and the remaining lifecycle/consent controls; this is not production chat or reflection. |
| [Rust orchestrator](../rust/src/orchestrator.rs) | Coordinates existing provider-backed agent work. | A separately reviewed local execution path; existing cloud work must not become unattended reflection. |
| [Flutter runtime controller](../lib/neura_runtime/neura_runtime_controller.dart) | Coordinates app runtime events and room memory behavior. | Explicit engine status, consent, cancellation, and resource controls. |
| [Local app API](NEURA_API_SYSTEM_UPGRADES.md#3-local-app-api-v1) | Offers authenticated, visible-session proposals for native review. | Keep this contract intact when integrating an engine. It is distinct from the Rust WebSocket sidecar. |

The synthetic implementation extends the Rust runtime and existing Flutter
controls. Further work must not replace working interaction or approval paths
merely to introduce a separate engine process.

## What ongoing reflection and learning mean

Reflection means bounded, local work over explicitly approved inputs: organizing
known information, identifying an inconsistency, reviewing a correction, or
preparing a suggestion for the user. The engine sleeps between permitted events
or scheduled work. It does not run an unrestricted, continuous inference loop.

Learning initially means reviewed updates to preferences, corrections, and
permitted memory. It does not mean automatic model retraining, self-modifying
code, or permission changes. A model-generated interpretation is a proposal,
not an established fact about the user.

Every proposed memory should identify its approved source, purpose, relevant
consent, and uncertainty. Keep proposals separate from admitted memory until the
user reviews them. Allow rejection and correction without treating repeated
model suggestions as independent evidence. Account for sensitive content and
derived information, not only the original input.

## Required boundaries

- Start disabled. Explain the selected sources, purpose, retention, resource
  limits, and current activity before the user enables local reflection.
- Read only the sources the user selects and authorizes. Do not scan folders,
  listen through the microphone, observe other apps, or expand access on the
  strength of instructions found in a document or model response.
- Treat source text and generated suggestions as untrusted data. The runtime
  enforces policy independently of the model; the model cannot approve its own
  actions or grant itself permissions.
- Offer visible status, Pause, Stop, source removal, correction, and Forget
  controls. Stop must cancel active work and discard pending results. Revocation,
  Safe Mode, and recovery must invalidate work across asynchronous boundaries.
- Recheck consent and source validity before admitting any result. Removing or
  wiping a source must invalidate its pending and derived data so a delayed task
  or restart cannot restore information the user removed.
- Preserve owner, device, purpose, source, and sensitivity boundaries when using
  the [encrypted memory contracts](ENCRYPTED_MEMORY_FOUNDATION_v1.6.md) and
  [session adapter](ENCRYPTED_MEMORY_SESSION_ADAPTER_v1.6.1.md). Access to chat
  context is not blanket permission for long-term memory. The foundation requires
  a direct user gesture and a single-use lease of at most 15 minutes for each
  operation. Enabling reflection must not reuse that lease for background reads
  or expand the permitted memory classes.
- Keep reflection local. Every cloud turn, retry, fallback, and continuation
  retains the existing fresh preview and visible approval requirement described
  in [API and system upgrades](NEURA_API_SYSTEM_UPGRADES.md). No background cloud
  calls, cloud health probes, or background microphone access are introduced.
- A suggestion cannot execute an action. Execution must pass through the
  existing native policy and visible approval boundary. Never replay approved
  actions after cancellation, restart, consent expiry, or a changed payload.
- Preserve the local app API's loopback binding, session authentication,
  proposal-only endpoints, and shutdown on screen closure, backgrounding, or
  Safe Mode. An engine must not turn this API into an unattended control port.
- Keep the journal as the local authority and preserve the existing `updated_at`
  conflict rule. Reflection does not silently rewrite or synchronize journals.
- Bound CPU time, memory, queue size, storage, and battery use. Pause when budgets
  are exhausted. Record content-free operational diagnostics, never prompts,
  memory text, credentials, or selected-file contents.

The initial scope is a user-enabled Windows session. Keeping the engine running
after the app closes requires a separate, explicit background-host design with
visible controls and revocable permission. Android support needs its own
lifecycle and battery validation; it must not assume desktop behavior.

## Implementation milestones

1. **Engine lifecycle and controls.** Define explicit disabled, idle, working,
   paused, and error states, with a session generation that invalidates old work.
   Add bounded scheduling, cancellation, and Flutter status controls. Secure the
   Rust IPC boundary with local-only binding and revocable authentication before
   admitting personal data. Start with synthetic inputs and no external actions.
2. **Local model adapter.** Select a model only after checking target hardware,
   license, storage, and measured resource use. Require an explicit installation
   choice; do not silently download models or fall back to a cloud provider.
   Distinguish unavailable, echo/test, and real model modes in diagnostics.
3. **Approved sources and memory review.** Integrate scoped source selection,
   provenance, quarantined proposals, review, correction, and deletion with the
   existing memory contracts. Fail closed when consent is missing or revoked.
4. **Companion suggestions.** Connect reviewed local suggestions to existing UI
   flows. Keep preparation separate from execution, and retain native approval
   for every action. Show the evidence and uncertainty needed to review a
   suggestion without exposing private internal traces.
5. **Optional background availability.** Evaluate a separately enabled host only
   after the session runtime meets the gates below. Specify startup, shutdown,
   notification, battery, update, and revocation behavior before implementation.

Each milestone should be a reviewable change with its own evidence. This vision
does not mark any milestone complete.

## Acceptance gates before enabling reflection

- Demonstrate that disabled, paused, stopped, revoked, recovery, and Safe Mode
  states prevent new work and reject late outputs. Restart must not replay work
  or actions from an earlier session.
- Verify that unapproved sources cannot be read, proposed memory cannot admit
  itself, and forgetting a source cannot be undone by queued or persisted work.
- Exercise cancellation and resource exhaustion under load, with bounded queues
  and measured limits selected for the supported hardware before opt-in is
  offered. Avoid an unbounded idle loop or unbounded diagnostic storage.
- Demonstrate with controlled tests that local reflection emits no provider
  requests, microphone capture, or external actions, including during errors.
- Verify that unauthorized local clients cannot submit engine work or read
  private state, and that revocation immediately ends their access.
- Test the actual selected model and lifecycle on supported Windows hardware;
  record latency, memory, disk, power, and cancellation results. Automated tests
  and echo responses do not substitute for this device evidence.
- Pass the repository's applicable CI and review requirements. Keep physical
  device checks and existing storage/build gates intact.

The user remains in control of what Neura learns, remembers, and does throughout
these stages.
