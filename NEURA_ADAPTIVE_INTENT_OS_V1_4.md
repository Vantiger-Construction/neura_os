# Neura Adaptive Intent OS — 1.4 real-beta foundation

Neura Adaptive Intent OS is a local-first computing layer that changes plan
size, information density, and consent strength according to a practical,
explainable estimate of the user's available cognitive bandwidth. It is not a
medical diagnostic system.

The research package now identifies as **1.4.0+7**.

## Product-facing Phase 4

Phase 4 replaces the remaining demonstration-only boundaries with four
production-facing components.

### 1. Live local signals

The live adapter can use only normalized, privacy-safe values selected during
onboarding:

- the most recent 0–10 mood score and timestamp;
- the user-selected Focus Mode;
- active-quest and recent quest-completion counts;
- bounded in-app surface-switch and interruption counts.

The adapter does not place mood notes, journals, therapy text, dreams, messages,
memory content, quest titles, or other raw personal copy into the Cognitive
Bandwidth Engine. Each source can be disabled independently. Source failures
degrade locally instead of preventing Neura from starting.

### 2. Encrypted outcome learning

Derived outcome receipts are now stored in a bounded encrypted local history
using Neura's OS-backed AES-GCM key. A receipt contains only:

- session and timing identifiers;
- selected bandwidth mode;
- completed, deferred, blocked, and external step counts;
- completion ratio;
- perceived effort;
- satisfaction;
- interruption count.

Raw goals, plan text, step titles, step descriptions, messages, journal text,
and therapy text are not written to the outcome history. The history is capped
at 100 records, loaded across restarts, and cleared before the device encryption
key is removed during a full local-data wipe.

### 3. One real reversible action

Adaptive Intent can prepare one executable capability:

> Create a reversible local quest from one explicitly selected local-write step.

The bridge does not execute the quest. It verifies the current cognitive mode,
Safe Mode, the step type, the Capability Registry classification, reversibility,
absence of external effects, and a direct user gesture. It then creates an
`askApproval` candidate for the existing Action Review screen.

The existing Action Loom remains the authority for exact payload binding, fresh
approval, Safe Mode and policy revalidation, idempotent execution, durable
action metadata, crash recovery, and undo. No second executor was introduced.

### 4. Opt-in onboarding and controls

Adaptive Intent is off by default. Onboarding explains what it does, what it
does not do, what is stored, and which signal sources are available. Users can
enable or disable each source, turn the feature off, and clear all associated
local data through Neura's existing data controls.

Disabling the feature revokes an active in-memory session. Safe Mode blocks new
sessions, progress changes, live action preparation, and outcome mutation.

## Still blocked

Adaptive Intent cannot autonomously send a message, contact another person,
change a calendar, schedule an external notification, purchase anything, move
money, call cloud AI, or execute an unknown capability. Those effects remain
blocked or review-only.

## Validation contract

The Neura 1.4 workflow requires, on the same commit:

1. `flutter pub get`;
2. canonical package-mode Dart formatting;
3. `flutter analyze --fatal-infos`;
4. all Cognitive, Constitution, Intent Compiler, and Adaptive Intent tests;
5. Neura's complete Flutter test suite.

Phase 4 adds focused coverage for enrollment, disabled-source behavior, live
signal fusion, encrypted bounded outcome restoration, data-wipe clearing, Safe
Mode refusal, exact local-quest proposal shape, approval requirements, and
runtime restoration without raw-goal persistence.
