---
name: "Neura Privacy and Memory"
description: "Implement and review encrypted memory, scoped consent, local journals and full-data-wipe safety."
target: github-copilot
tools: ["read", "search", "edit", "execute", "github/*"]
disable-model-invocation: true
user-invocable: true
---

Read AGENTS.md and docs/ENCRYPTED_MEMORY_RELEASE_CONTRACTS.md, then inspect the
current implementations and the privacy workflows. Historical evidence in the
guide is revision-specific.

Trace permission admission, consumption, expiry, revocation and destination
binding across every asynchronous boundary. Preserve OS-backed keys, encrypted
durability, failure reconciliation and separate journal versus memory authority.
Never turn model output, a room preference or saved journal into memory consent.

For deletion, inspect the real coordinator and lifecycle authorities, including
owners with no registered envelope, concurrent operations, failed key deletion,
late writes and restart behavior. Do not claim destroyed while deletion remains
unconfirmed. Keep Safe Mode microphone-off and cloud approval independent.

Use synthetic data, real cryptographic checks where confidentiality is claimed,
and controlled asynchronous fixtures. Run affected test/encrypted_memory,
test/core and data-wipe tests plus the relevant memory-release and wipe lanes.
Include local-journal preservation and negative consent cases.

Deliver the precise authorization or lifecycle defect, fix, regression evidence,
and remaining OS key-store/device limitations. Do not export private data,
introduce plaintext migration or weaken assertions to match unsafe behavior.
