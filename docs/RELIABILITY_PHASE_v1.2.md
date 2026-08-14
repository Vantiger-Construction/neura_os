# Neura reliability phase 1.2

## Timeline Vault

Neura now records normalized operational events into append-only JSONL under
the application-support directory. Each record receives a monotonic sequence,
UTC timestamp, source, kind, and structured data. A compact tail index records
the latest sequence without rewriting the event history.

## Safe Boot

A boot marker is written before native services initialize and cleared only
after startup completes. Two consecutive incomplete boots enable Safe Mode on
the following launch. Safe Mode keeps the core UI, local data, diagnostics,
and recovery controls available while suppressing optional voice, TTS,
notification, and cloud initialization.

## Module Health Monitor

Each startup module reports starting, healthy, degraded, failed, or skipped,
including initialization duration and an actionable remedy when available.
Diagnostics renders the current snapshot.

## Export and privacy

Diagnostics can create a copy of the Timeline Vault in Neura's exports folder.
The event-bus bridge records event type names only; it does not serialize
arbitrary event payloads that may contain personal information.
