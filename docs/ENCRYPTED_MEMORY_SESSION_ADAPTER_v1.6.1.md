# Neura encrypted memory session adapter 1.6.1

This slice adds an in-process adapter for explicit `remember` and `recall`
operations. It retains admitted records only in memory for the current process
lifetime. It does not claim encryption at rest and has no serialization API.

## Runtime boundary

Every access requires:

- an exact, unexpired, direct-user-gesture consent lease;
- a direct user gesture in the runtime safety context;
- Safe Mode to be inactive;
- Recovery mode to be inactive; and
- the exact active key-lifecycle generation.

Remember and recall consume separate single-use leases. A missing recall also
consumes its lease so the request cannot be replayed as a record-existence
probe. Duplicate record identifiers are rejected rather than overwritten.

The adapter can be suspended and cleared during a safety transition. Resuming
always starts an empty session. Clearing is protective only and grants no read,
write, export, wipe, or execution authority.

## Explicit exclusions

This adapter does not register itself globally, persist or encrypt data, migrate
legacy memory, capture background data, access a model, synchronize devices,
export records, perform the durable wipe contract, or call Action Loom. Those
remain separate future integrations with their existing approval boundaries.
