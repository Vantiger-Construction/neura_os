# Neura 1.5 — Living Intelligence

Neura 1.5 adds a safety-first foundation for private inference, deterministic
emergency commands, explainable decisions, isolated contexts, signed skills,
lifelike presence, plan simulation, A/B recovery, Android function exposure,
and encrypted device continuity.

The package milestone is `1.5.0+1`.

## Non-negotiable authority rules

1. Safe Mode always wins.
2. Unknown capabilities fail closed.
3. Model output never grants execution authority.
4. Money movement remains blocked.
5. External, sensitive, or destructive effects require a direct user gesture,
   fresh approval, and the existing Action Loom.
6. New systems are opt-in and disabled by default.

## 1. Private Neural Core

`NeuraLocalModelRouter` selects an available local backend before considering a
cloud backend. Adapter contracts are included for:

- Windows local inference;
- Android on-device inference;
- portable ONNX-style local inference;
- explicitly enabled cloud inference.

The adapters receive only a bounded request selected by the caller. Private
records cannot fall back to cloud inference. Native SDK bindings and model
downloads remain platform integration work and are deliberately unavailable
until a trusted adapter is supplied.

Supported foundation purposes are:

- summarize visible content;
- classify intent;
- explain a decision;
- generate alternatives;
- create a draft.

Generated text has no action authority.

## 2. Reflex Safety Layer

The deterministic reflex parser handles exact safety commands without calling
a model:

- Stop
- Cancel
- Be quiet
- Stop listening
- Enter Safe Mode
- Undo that
- Do not remember this
- Clear this conversation

Bindings can cancel generation, stop speech and listening, release audio focus,
request Safe Mode, undo through the existing action system, and clear only the
requested local context.

## 3. Trust Lens

`NeuraDecisionReceiptV2` records only bounded derived labels:

- interpreted intent;
- evidence labels;
- excluded-source identifiers;
- alternatives;
- confidence;
- reversibility;
- approval mode;
- undo description.

Raw journals, therapy text, messages, prompts, conversation copy, and mood
notes are rejected from evidence labels.

## 4. Context Capsules

The default isolated contexts are:

- Personal
- Work
- Care
- Kids
- Private Vault
- Guest

Each capsule declares an encrypted partition id, data categories, allowed
capabilities, cloud policy, and retention period. Cross-capsule transfer
requires a direct user gesture and fresh approval. Kids and Guest contexts have
additional hard denials.

## 5. Signed Skill Capsules

A skill manifest must declare:

- reverse-domain id and version;
- capability ids;
- private-data classes;
- permissions;
- network policy and exact hosts;
- Safe Mode behavior;
- a trusted signature.

Unknown, critical, money-moving, arbitrary-code, shell, PowerShell, unrestricted
filesystem, native-library-loading, wildcard-network, and unsigned skills are
rejected. Repeated crashes quarantine a skill.

This release validates manifests and health. It does not dynamically load
arbitrary Dart or native code.

## 6. Presence Engine 2.0

The deterministic state machine coordinates:

- idle, listening, thinking, speaking, interrupted, and quiet states;
- user barge-in;
- generation cancellation;
- speech stop;
- audio-focus release;
- echo/self-listening cooldown;
- concise, reading, coaching, comforting, and quiet delivery modes.

It does not infer a clinical or emotional diagnosis.

## 7. Future Paths Simulator

The simulator creates non-executable views of a plan:

- fastest;
- safest;
- lowest cost;
- lowest effort;
- most reversible.

Every result explicitly reports `executable == false`. A path containing an
external or irreversible step is marked as requiring approval.

## 8. Self-Healing Runtime 2.0

The A/B controller models:

- Slot A;
- Slot B;
- minimal Recovery;
- signature and checksum prerequisites;
- first-frame, runtime-payload, and launch-sentinel canaries;
- promotion;
- rollback;
- repeated-failure quarantine.

Platform installers still perform file staging, signature verification, and
process launch. The controller owns the deterministic state transitions.

## 9. Android Intelligence Bridge

Only these function ids are accepted:

- `open_neura`
- `open_room`
- `start_selected_ritual`
- `show_user_quests`
- `draft_quest_for_review`
- `open_safe_mode_controls`

Draft creation requires a direct user gesture and remains an in-app review
operation. Unknown functions, including money or private-export requests, are
blocked. In Safe Mode, only Neura and its recovery controls may open.

## 10. Encrypted Device Continuity

The registry supports:

- verified device pairing;
- per-device data-category policy;
- revocation;
- authenticated encrypted-envelope validation;
- anti-replay sequence checks;
- deterministic metadata conflict resolution;
- full revocation during data wipe.

The Dart layer never accepts plaintext for continuity envelopes. Platform crypto
must supply ciphertext, nonce, and authentication tag.

## Source layout

```text
lib/living_intelligence/
  android_intelligence_bridge.dart
  context_capsules.dart
  device_continuity.dart
  future_paths_simulator.dart
  living_intelligence.dart
  neura_living_intelligence_runtime.dart
  neura_safety_policy.dart
  presence_engine.dart
  private_neural_core.dart
  reflex_safety_layer.dart
  self_healing_runtime.dart
  signed_skill_capsules.dart
  trust_lens.dart
```

## Validation

The Neura 1.5 workflow requires:

1. no committed merge markers;
2. dependency restore with Flutter 3.44.7;
3. canonical Dart formatting;
4. fatal-info analysis;
5. all Living Intelligence tests;
6. the complete Flutter test suite.

Native model SDKs, production package signing, signed skill distribution,
platform crypto, Android system registration, physical-device acceptance, and
installer A/B file operations remain explicit release-administration or native
adapter work. The foundation does not pretend those external integrations are
already provisioned.
