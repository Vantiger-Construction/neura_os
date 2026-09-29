# Encrypted memory provenance and quarantine v1.7

This slice strengthens the process-local encrypted-memory seam. It still does
not claim durable encryption or persistence. The goal is to make later durable
adapters inherit a fail-closed access and admission contract.

## Retrieval scope

A consent lease now binds all of these fields before lookup:

- authenticated owner ID;
- current device ID;
- capsule ID;
- admitted memory class;
- immutable source kind; and
- exact sensitivity.

The adapter does not retrieve a broad result set and filter afterward. A
mismatch fails before index access, and each lease remains direct-gesture,
short-lived, and single-use.

## Provenance

Every candidate carries bounded metadata alongside its value:

- source and source ID;
- author ID;
- a non-content policy reason;
- trust tier;
- integrity state and integrity tag; and
- UTC observation and optional review times.

The reason field is for a stable code such as `user_tapped_remember`, not
copied journal, prompt, or conversation content.

## Quarantine

Unverified input is not recallable. Model output, voice inference, and web
content always enter quarantine unless a separate direct user review releases
that exact candidate with verified integrity. The original source remains
immutable after release. Rejection removes the process-local candidate and
grants no read authority.

Authenticated user input or a verified local import can be admitted directly
when its integrity tag is present. No model-facing method can promote its own
trust tier.

## Preserved safety boundaries

- Safe Mode and Recovery block remember, review, and recall before consuming
  consent.
- Key generation is checked before any operation.
- Clearing or suspension removes both admitted and quarantined candidates.
- Quarantined candidates are indistinguishable from missing records through
  the recall API.
- There is no serialization, sync, background capture, cloud disclosure,
  autonomous write, or Action Loom path.

## Validation focus

Run:

```text
flutter test test/encrypted_memory
```

The tests cover exact owner/device/source/sensitivity scope, single-use leases,
model and voice quarantine, explicit release and rejection, Safe Mode,
Recovery, stale keys, clearing, and missing-record behavior.
