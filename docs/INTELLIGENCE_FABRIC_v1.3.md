# Neura Intelligence Fabric 1.3

Neura 1.3 gives proactive features one local-first, inspectable decision
system instead of a collection of unrelated “smart” cards.

1. The **Signal Graph** converts existing local stores into short-lived,
   privacy-labelled evidence.
2. The **Opportunity Radar** runs deterministic specialists that can propose
   candidates but cannot perform side effects.
3. The **Autonomy Kernel** scores benefit, confidence, urgency, disruption,
   and capability risk, then applies attention, privacy, consent, and Safe Mode
   policy.
4. Existing **Guardrails** get a final veto before a prompt reaches the UI.
5. The UI shows a **Decision Receipt** and requires a user gesture.
6. A state-changing capability must pass the **Action Loom Approval Broker**
   again immediately before execution.

## Local signals, not surveillance

Each observation has an ID, source, timestamp, useful lifetime, confidence,
and sensitivity. Fusion drops expired or future-dated observations, decays
stale evidence, reduces confidence when numeric signals conflict, and keeps a
bounded evidence set.

The runtime adapter currently supports numeric mood history, active quests and
seven-day quest momentum, user-authored goals, and explicit Focus Mode. Health,
sleep, wearable, and activity signals are omitted when unavailable; they are
not treated as zero. The adapter does not read raw journals, therapy entries,
dream content, mood notes, or memory records.

Sensitive signals remain off until the user opts in. When they are off, even
sensitive evidence IDs are excluded from the persisted receipt.

## Opportunity Radar

The first specialists can suggest a gentle reset after a low recent mood, a
five-minute step for a stalled quest, a small quest draft for a goal without an
active quest, or a short focus sprint. Candidate IDs are stable for the same
rule, subject, and evidence, so Neura can deduplicate locally without a cloud
identity. The Radar performs no write, navigation, notification, or network
request.

## Consent and Action Loom

Capabilities declare risk, reversibility, external side effects, and approval
policy. Unknown capabilities fail closed as critical and blocked. Read-only
suggestions may be evaluated automatically but still require the user to open
them. Reversible local changes require a direct gesture or explicit approval;
sensitive and external effects require fresh approval every time. Critical
capabilities, including money movement, cannot execute autonomously.

The Approval Broker:

- binds an approval to the exact candidate, receipt, evidence, and payload;
- revalidates policy immediately before execution;
- expires stale proposals and rejects implicit retry after uncertain failure;
- deduplicates concurrent submission, execution, and undo calls;
- keeps undo idempotent and available through Safe Mode when safe to do so;
- revokes process-local authority during a full data wipe.

The first bound executor is intentionally narrow. Opening a goal-to-quest
review makes no change. Approval creates one deterministic local quest using a
cryptographic payload fingerprint. A durable execution record can recover an
interrupted write and prevents the same approved payload from being applied
again after restart. Undo removes the quest only while no progress has been
recorded.

## What is stored

Decision history is bounded to 100 receipts. It stores identifiers, decision
and outcome, risk and priority score, policy reasons, permitted evidence IDs,
and timestamps. It does not store the private recommendation title or body.
Timeline Vault receives metadata-safe fields only, and optional learning runs
only while `allowLearning` is enabled.

Action Loom also keeps bounded consent and execution metadata: action,
candidate, receipt, capability and quest IDs; status and approval state;
timestamps; and a one-way payload fingerprint. Raw goal text, recommendation
copy, journals, and mood notes are not written to those ledgers.

## Cloud-tool consent

Room policy still limits which tools a model may request, and the app checks
that policy again at execution time. Neura then displays a concrete
confirmation before each request to:

- share recent mood history;
- save a mood check-in locally;
- navigate to another room; or
- change the presentation tone.

A confirmed history share contains dates and 0–10 mood scores only. Existing
mood notes are never included. Saving a check-in happens in the local UI
handler after confirmation, and the cloud tool result reports only whether the
numeric check-in was saved. A decline is returned as a denial, not treated as
authority for a later call.

## Attention controls

Users can disable proactive intelligence, pause it for 24 hours, set an
overnight quiet window, choose a daily suggestion cap, hide explanation links,
and opt into sensitive local signals. Repeated dismissals extend cooldown.
Deep Work, Wind Down, Safe Mode, and storm context suppress nonessential
interruptions. Quota and cooldown are committed only after a card is actually
rendered.

## Encryption and complete data removal

Memory encryption uses a random AES-GCM key in the operating system credential
store. A new key is accepted only after a verified secure write. During legacy
migration, the old key remains authoritative until its matching secure copy is
verified and a commit marker is stored. If an expected secure key is missing
or the credential store is unavailable, Neura refuses to generate a replacement
that would strand existing encrypted records. In-flight crypto work is
invalidated when a wipe begins.

Full local-data removal has transactional completion semantics: it reports
success only if every known step completes. Neura first latches Safe Mode,
cancels cloud generation, stops microphones and scheduled notifications,
drains persistent writers, and clears in-memory controllers. It then verifies
credential and encryption-key deletion, clears preferences, and deletes only
the known app-owned document, support, recording, and temporary paths.

All deletion categories are attempted even if one fails, and the UI receives
the complete failure-category list. An incomplete wipe leaves write paths and
keys suspended, preventing late queued work from recreating deleted data. Only
regenerable local stores resume after total success; Safe Mode plus native and
provider credential access remain latched until restart. This is a fail-closed
completion boundary, not a rollback of data already deleted.

## Safe Mode and platforms

Safe Mode is enforced inside cloud AI, native Swarm, ambient listening, wake
word, TTS, notification, proactive-intelligence, startup, and shell paths.
This prevents a direct service call from bypassing startup suppression.
Clearing the persisted marker prepares a normal next launch while keeping the
live process safe; Diagnostics indicates that restart is required.

Desktop window setup runs only where supported. Windows retains Neura's
secondary mascot-engine role; macOS attempts primary-window initialization
without making it a boot requirement; web and mobile avoid the desktop plugin
path. The native Rust Swarm is currently packaged for Windows only and web uses
a safe no-op fallback. macOS secure storage is configured with its keychain
access group.

## Startup and release gate

The Intelligence controller hydrates only after preferences, Focus, and Human
Preferences. Safe Boot is a critical startup gate; if its persisted state
cannot be established, startup stays in Safe Mode. Optional service failures
remain recoverable and are recorded in Module Health and Timeline Vault.

GitHub Actions installs its pinned Flutter version, restores dependencies,
captures any Dart formatting patch, runs analysis and Flutter tests, then
builds Windows and Android recovery artifacts only after verification. Package
names and build versions are derived from `pubspec.yaml`, and the verification
artifact retains logs plus the generated `pubspec.lock` when available.

This packaging environment does not include Flutter, Dart, Rust, or Windows
PowerShell, so these tests and builds have not been run here. Before release,
run the GitHub workflow and `BUILD_ALL_NEURA_UPGRADES.bat` on a configured
Windows build host; do not infer a passing build from this document.
