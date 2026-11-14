# Inactive forecast calibration foundation

This is a bounded Rust-only utility based on the useful forecast portion of the
recovered attunement proposal. It is not the full proposal and enables no feature.
It adds no Dart/FRB/sidecar API, capture, persistence, background task, learning,
model call, permission, memory grant, reputation update or autonomy decision.

## Contract

- The application supplies a numeric `SourceId(u16)` from its own registry. No
  source names, event text, user data strings or caller-chosen forecast IDs are
  retained. A number is not proof of source identity or consent.
- `record` accepts only finite probabilities in `[0, 1]`. It generates an opaque
  immutable ID containing a ledger-instance number and an increasing sequence.
  There is no replacement, reattribution, restore or deserialize API.
- IDs are unique among ledgers in this loaded library instance. Both instance
  allocation and per-ledger sequence allocation fail on exhaustion, never wrap.
  Clear, forget, expiry and scored-history eviction do not reset the sequence.
  Handles must not cross a process restart/library reload or be used as durable
  identifiers or authorization tokens. The ledger is deliberately not Clone.
- The owner supplies one nondecreasing logical clock in **seconds**. Equal times
  are allowed. A deadline must be strictly after admission and at most seven
  days ahead. Resolution must occur strictly before the deadline: equality and
  late arrivals expire unscored, even if an outcome occurred earlier. There is
  no separate event-time/backdating API.
- Every time-bearing call first observes `now`, advances the watermark and
  expires records. This maintenance still occurs if admission or resolution
  subsequently fails. A backward timestamp returns an error without mutation.
  The caller must provide its trusted clock, not model-supplied timestamps.
- At most 256 open forecasts are retained. Full capacity rejects the new one
  without evicting live work. Expired entries are removed before capacity checks.
  At most 2,000 scores are retained globally across sources; the oldest resolved
  score is evicted before admitting another. Scores also expire at age 90 days.
  Eviction can change a source's visible statistics; it never permits replay.
- Maintenance runs only on explicit calls. Counts, summaries and calibration
  reflect the last accepted time. Call `advance(now)` before displaying them;
  the age limit is not a background wall-clock deletion guarantee.

All stored records have fixed-size numeric fields. There are no replay
tombstones, unbounded labels, configurable allocation sizes or input collections.
Open/scored scans are bounded by the caps above. Calibration always returns ten
bins, with no heap allocation; summaries also require no temporary allocation.
Allocation requests are fixed per ledger, not a process-wide admission budget.
An eventual runtime owner must bound the number of ledger instances and callers.

## Reading the statistics

Brier score is the mean squared error of binary probabilities, in `[0, 1]`.
`skill_against_half_probability = 1 - mean_brier / 0.25` compares specifically
with predicting 50% for every event. It lies in `[-3, 1]`; it is **not** a
prevalence-adjusted no-skill benchmark and does not establish calibration.
For rare events, a constant low probability can beat 50% without useful
discrimination. No reputation multiplier is produced.

Calibration bins compare mean predicted probability with observed event
frequency. They include sample counts; empty bins contain `None`, not invented
measurements. No confidence interval or minimum-evidence certification is claimed.
Only retained, resolved outcomes are summarized. Selective resolution, changing
event definitions, short histories and global eviction can bias the result.
Unresolved/expired forecasts are never treated as false outcomes.

## Before any runtime integration

Keep this disconnected until the actual integration is separately reviewed.
The only reviewed integration so far is display-only suggestion calibration,
which uses a Dart port of this contract; see
[SUGGESTION_CALIBRATION_INTEGRATION.md](SUGGESTION_CALIBRATION_INTEGRATION.md).
This Rust module itself remains disconnected.
Define consent, stable source/event definitions, trustworthy outcome evidence,
source ownership, UI wording and acceptable retention. Preserve current manual
choices, Safe Mode, exact-request cloud approval and all autonomy gates. Existing
Teach Neura's two explicit preferences do not authorize inferred learning.
No automatic imports of chats, journals, encrypted nodes or other personal data.

If persisted later, require OS-backed encryption, schema/input bounds, revocable
session/profile ownership, cancellation, late-completion rejection, writer drain
and verified deletion. Do not persist these process-scoped handles unchanged.
Clear/forget remove logical records only. They do **not** zero allocations,
scrub process dumps, erase copies/returned summaries or clear external storage.
Clear retains numeric ID/time watermarks to prevent replay and clock rollback.

## Validation

Synthetic Rust tests cover invalid inputs, capacity, expiry, rollback, identity,
replay, source isolation, retention and score/calibration invariants. No real
forecasts or personal fixtures are included.

On November 12, 2026, the isolated Linux x86_64 draft was checked with the official
pinned Rust 1.99.1 toolchain, without changing dependencies or lockfiles:

- `cargo fmt --manifest-path rust/Cargo.toml --all -- --check`: passed.
- Standalone `rustc --edition 2021 --test -D warnings` compilation of the forecast
  module and its 23 synthetic tests: passed; all 23 tests passed.
- `cargo test --manifest-path rust/Cargo.toml --locked --all-targets`: passed,
  with 156 tests across eight targets, including the 23 forecast tests.
- `cargo clippy --manifest-path rust/Cargo.toml --locked --all-targets -- -D warnings`:
  passed.

The compiler exposed a deprecated atomic method; the allocator now uses
`try_update`, preserving fail-closed exhaustion. Independent review confirmed
that change and the formatter-only edits preserved the intended behavior.

These results validate the inactive Rust foundation, not a user-facing feature.
No Windows/Android build, Flutter suite, real-device or model test was run for
this draft. Run the applicable existing CI lanes on the final revision before
release acceptance. The Flutter 3.47.9 / FRB 2.13.0 pins and native platform
behavior are unchanged.
