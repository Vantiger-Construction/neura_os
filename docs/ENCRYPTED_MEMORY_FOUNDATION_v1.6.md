# Neura encrypted memory foundation 1.6

This change defines policy contracts and tests only. It does not register a
runtime service, open a database, capture background data, migrate existing
memory, call a model, synchronize a device, or grant execution authority.

## Admitted memory classes

The MVP can represent only:

- a note the user explicitly asks Neura to remember;
- an explicit preference;
- a bounded continuity fact;
- a user-approved derived label.

Raw conversations, messages, journals, therapy content, dreams, mood notes,
goals, plan copy, quest titles, credentials, biometrics, and device details are
not representable by the contract.

## Consent

Every operation requires an exact Context Capsule, operation, memory class,
direct user gesture, and lease of at most 15 minutes. Leases are single-use.
Scope mismatch, expiry, reuse, indirect initiation, whitespace ambiguity, and
control characters fail closed.

This consent proves memory access only. It never authorizes Action Loom or any
external mutation.

## Key lifecycle

The lifecycle is monotonic and generation-bound:

`absent -> active -> rotating -> active`

An active or rotating key may be suspended. Destruction is terminal. Reads and
writes are refused unless the expected generation is active. A future adapter
must use the operating-system credential store and existing AES-256-GCM
facilities; key material must never be stored beside ciphertext or exported in
diagnostics.

## Export

Exports are limited to explicitly selected record identifiers, one capsule, a
user-selected destination, and a maximum 15-minute plan. Export contracts do
not permit ambient sharing or cloud fallback.

## Wipe

A valid wipe must stop writers, delete ciphertext, destroy the key, and verify
both deletions. Partial success is failure and must keep memory suspended.
Integration with the existing full-data wipe is deliberately deferred until the
foundation and release-readiness stack are validated.
