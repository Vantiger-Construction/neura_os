# Neura 1.5.1 — Consent-Scoped Intelligence and Turn Safety

Neura 1.5.1 is a bounded follow-up to the Neura 1.5 Living Intelligence
foundation. It strengthens private inference, conversational interruption, and
Neura's permanent client-first character without expanding execution authority.

The package milestone is `1.5.1+2`.

## What this upgrade adds

### 1. One-use cloud inference consent

A reusable `allowCloudInference` flag is no longer sufficient by itself for
cloud fallback. A caller must also issue a short-lived permit that is scoped to:

- one model purpose;
- one Context Capsule id;
- an exact set of derived data labels;
- one use;
- a bounded expiration time.

Issuance requires a direct user gesture, fresh in-app approval, and explicit
cloud opt-in. Safe Mode, Recovery mode, revocation, expiration, scope mismatch,
and private records all fail closed.

The router validates consent before probing a cloud backend and consumes the
permit only after an eligible cloud backend is available. Local backends remain
first and do not consume cloud consent.

A consent permit never authorizes an action. It only permits one bounded text
request to reach an already configured cloud model adapter.

### 2. Conversational Turn Coordinator

`NeuraConversationTurnCoordinator` owns one visible generation turn at a time.
It provides:

- deterministic turn ids;
- cancellation of stale generations;
- Presence Engine state coordination;
- user barge-in that cancels generation, stops speech, and releases audio focus;
- quiet-mode cancellation;
- per-delta, total-character, and delta-count limits;
- rejection of unsafe control characters;
- a required final stream delta;
- non-authoritative display-only output envelopes.

Safe Mode is re-checked during streaming, so activating Safe Mode stops later
model deltas instead of allowing an already-started generation to continue.

This layer does not call `flutter_tts` directly. Native speech remains behind
existing bindings, which avoids representing the known Windows TTS adapter work
as completed.

### 3. Heart-of-gold response guidance

`NeuraCompassionateResponsePolicy` makes the permanent character charter usable
as bounded model-adapter guidance. It keeps these rules non-tunable:

- kindness, patience, dignity, and sincere best effort;
- clear explanations, including why a suggestion may help;
- honest separation of observation, inference, and uncertainty;
- no pressure, shame, manipulation, or dependence;
- consent before sensitive memory or consequential preparation;
- no diagnosis or claim to replace a qualified professional;
- generated text never grants execution authority.

Audience behavior is explicit:

- Adult: warm and direct.
- Teen: gentler, with extra care and no condescension.
- Child: simple, calm language with the strictest guardrails, no secret or
  private-contact requests, and trusted-adult involvement for meaningful or
  sensitive decisions.

Support signals such as frustration or overwhelm must be supplied explicitly by
the caller from the current visible interaction. The policy does not infer a
clinical or emotional diagnosis and does not silently read private history.

### 4. Action Loom fresh approval leases

A stored `explicitUserApproval` Boolean is no longer the only execution evidence
for capabilities configured as `everyTime`, sensitive, external, critical, or
side-effecting. Action Loom now issues a process-local lease that is:

- scoped to one action id, immutable candidate id, decision receipt id, and
  registered capability id;
- limited to at most two minutes and never longer than the candidate itself;
- replaced and revoked when the user approves the action again;
- rejected when missing, not yet valid, too close to expiry, expired, revoked,
  consumed, or mismatched;
- consumed once inside the registered local-plan capability executor before any
  quest ledger or quest data mutation begins;
- cleared during local-data wipe and process-local approval-cache reset.

Action Loom also requires at least five seconds of remaining lease lifetime
before beginning broker revalidation. This avoids deliberately starting a
mutation on evidence already at its expiration boundary. A stale or mismatched
lease causes the reviewed action to be denied and requires a new reviewed
submission instead of silently refreshing authority.

The bounded Action Loom audit record stores only lease id, state, and UTC
issuance, expiration, consumption, or revocation times. It does not store raw
proposal copy, prompts, goals, payload values, journal text, therapy records, or
conversation content.

Calling the internal broker's approval method directly does not bypass this
boundary: Action Loom's preflight requires a lease, and the local-plan executor
consumes the same exact-scope lease immediately before mutation. Device identity
and Context Capsule identity are not yet part of Action Loom's action model, so
cryptographic device/capsule binding remains explicit follow-up integration
rather than being claimed as complete.

## Runtime integration

`NeuraLivingIntelligenceRuntime` now exposes:

- the cloud consent registry;
- the compassionate response policy;
- the conversation turn coordinator;
- active permit and active-turn status;
- a guided request builder;
- data-wipe reset that cancels generation, clears permits, revokes continuity,
  resets skill health, and enters quiet mode.

Living Intelligence remains disabled by default. Safe Mode and Recovery mode
still win. Action Loom remains the only authority for real mutations, and money
movement remains blocked.

## Validation

The focused workflows require:

1. no unresolved merge markers;
2. canonical Dart formatting;
3. fatal-info analysis;
4. all Living Intelligence tests;
5. fresh approval lease unit tests;
6. Action Loom approval-bypass, audit-privacy, expiry, and data-wipe tests;
7. the complete Flutter suite on hosted validation.

Native model SDKs, production credentials, platform secure storage, package
signing, speech-engine replacement, cryptographic Action Loom device/capsule
binding, Android system registration, physical-device acceptance, and installer
file operations remain explicit platform work.
