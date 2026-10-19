# Encrypted-memory release-contract evidence

This is an engineering verification record for the existing P1 task
[Validate encrypted memory release contracts](https://app.notion.com/p/3f4cff6b3f43818eb64ae3946aea4c31).
Synthetic automated validation does not complete physical-device acceptance or
approve a public release. PR #133 and this review branch require human review.

## Source boundaries

- Reviewed default: [`08fd9493038ef2aa6274c3a12402d96299b5b1bb`](https://github.com/Vantiger-Construction/neura_os/commit/08fd9493038ef2aa6274c3a12402d96299b5b1bb).
- Merged history work: [PR #113](https://github.com/Vantiger-Construction/neura_os/pull/113),
  merge [`5395a0457b51f0d1da048b6526680d12218615f3`](https://github.com/Vantiger-Construction/neura_os/commit/5395a0457b51f0d1da048b6526680d12218615f3).
  Its graph, tail helper and graph tests are unchanged in the reviewed default.
- Unmerged wipe candidate: [PR #133](https://github.com/Vantiger-Construction/neura_os/pull/133),
  [`b822c48be5a871d5a5e8e88825205d70534216d0`](https://github.com/Vantiger-Construction/neura_os/commit/b822c48be5a871d5a5e8e88825205d70534216d0).
- Corrections and new regressions: [draft PR #141](https://github.com/Vantiger-Construction/neura_os/pull/141).

These are separate implementations: the legacy JSONL graph, a RAM-only scoped
session adapter, and a durable scoped adapter storing one encrypted envelope.
The scoped adapters have no production construction sites outside their own
libraries. Legacy graph queries do not acquire the foundation's consent leases.
The graph's raw chat history must not be relabeled as an admitted foundation
memory class: the foundation explicitly excludes raw conversations and journals.

## Requirement mapping

| Requirement | Implementation and actual test evidence | Limit of the evidence |
| --- | --- | --- |
| Bounded history tails | [`boundedStreamTail`](../lib/core/memory/bounded_stream_tail.dart), graph `recentNodes`, `nodesOlderThan`, `nodesBetween`; [`bounded_stream_tail_test.dart`](../test/core/bounded_stream_tail_test.dart): 100,000-item history, matching order, physical blank/corrupt slots, nonpositive limits, empty streams | Bounds retained query records; scans remain O(history). No disk pruning, byte limit per record, or physical-device peak-RAM claim. |
| Decrypt only selected history records | [`memory_graph_service_test.dart`](../test/core/memory_graph_service_test.dart), `bounded encrypted graph queries discard in-flight results on wipe`: real AES-GCM, counted decryptions, recent/date-window limits, corrupt selected slots never backfilled, ciphertext unchanged after reads | Applies to graph queries. Durable scoped restore decrypts its complete envelope; it is not a record-at-a-time decryption implementation. |
| Corrupt records and I/O failures | Same graph test covers malformed JSON, invalid timestamps and bad ciphertext in selected positions. Tail tests propagate stream errors. [`memory_crypto_lifecycle_test.dart`](../test/core/memory_crypto_lifecycle_test.dart) rejects actual AES-GCM tampering. [`encrypted_memory_release_contracts_test.dart`](../test/encrypted_memory/encrypted_memory_release_contracts_test.dart) tests corrupt cold restore, no partial installation, and explicit retry | Arbitrary storage corruption, oversized lines, and native filesystem failure modes remain outside these fixtures. A simulated cold restore resets the registry; it is not an OS process restart. |
| Wipe generation and cancellation | PR #113 graph test invalidates all three in-flight queries, cancels their controlled streams, returns no stale data and keeps writers suspended. New crypto lifecycle tests revoke all four JSON/binary operations across the first await and keep destroyed handles terminal | Does not promise cancellation of an already-issued OS write or physical memory zeroization. Late writes require drain and cleanup. |
| Exact, direct, single-use consent, no more than 15 minutes | [`encrypted_memory_contracts.dart`](../lib/encrypted_memory/encrypted_memory_contracts.dart), [`encrypted_memory_contracts_test.dart`](../test/encrypted_memory/encrypted_memory_contracts_test.dart), session and durable adapter tests: exact owner/device/capsule/class/source/sensitivity/operation, direct gesture, separate remember/recall leases, missing-record consumption, replay refusal, pre-issue/exact-expiry and 15-minute boundary. New release tests cover backdated recall, clock rollback, expired encryption, queued expiry and expiry during native persistence | Legacy graph access is not routed through these leases. UTC clock injection is a trusted runtime/test seam, not caller authority to mint access. |
| No plaintext payload/key persistence | [`MemoryCrypto`](../lib/core/memory/memory_crypto.dart) uses AES-256-GCM and the OS credential store. New real-crypto tests inspect synthetic preferences/ciphertext, reject tampering, and verify no new preference-backed seed. The graph test checks real encrypted file bytes | Older durable adapter tests use a base64 fake (`cipher:`) to test orchestration; they alone prove no cryptographic confidentiality. Graph IDs, kinds, timestamps/outcomes and edges remain metadata. Legacy preference-backed key migration and explicit decrypted exports are separate acceptance concerns. |
| Key destruction, concurrency and full-wipe recovery | [`data_wipe_memory_contracts_test.dart`](../test/data_wipe_memory_contracts_test.dart) runs the actual full-wipe coordinator with synthetic stores, a held scoped write, ignored OS-key deletion, failure, retry and repeated wipe. It checks cache clearing, suspended then destroyed policy keys, no restored records and no late ciphertext. Real-crypto adapter tests independently reject stale cached recall, pending encryption/decryption and rekey adoption. Existing durable tests cover sibling serialization, forget/wipe ordering, ambiguous storage failure and reconciliation | In-process failure/retry evidence. Persistence of an incomplete wipe across process death, OS-key-store durability, and power-loss behavior are not established. |
| Safe Mode, recovery and quarantine | Existing session tests refuse Safe Mode/recovery before consuming leases and clear admitted/quarantined RAM on suspension. Existing durable tests recheck Safe Mode at commit; new tests change Safe Mode during restore. Full wipe keeps Safe Boot mic-off and all scoped storage instances suspended | Does not establish physical microphone shutdown. The RAM-only session adapter still requires its eventual runtime owner to call its suspension/clear hook. |
| Restricted export and rotation | Foundation tests enforce selected IDs, capsule, user-selected destination, bounded lifetime and monotonic policy-key states | Policy objects only. No scoped adapter export or actual device-key rotation implementation is claimed. Legacy graph `exportJson` is a separate API and is not governed by this export object. |

## Corrections proposed in PR #141

- Capture the crypto generation before the first await, check it before and
  after AES work, and prevent a destroyed handle from acquiring a new key.
- Revalidate the actual device-key authority before serving scoped cached data.
- Check durable consent against current UTC time at execution and persistence
  boundaries; reject rollback and expired queued work. An OS write already
  issued before expiry can finish, so an expired completion requires explicit
  reconciliation and fresh recall consent before content becomes accessible.
- Refuse recall during pending shared mutations so uncommitted corrections
  cannot be read from RAM. Failed persistence still restores the last snapshot.
- Full wipe synchronously suspends every registered durable storage state and
  clears admitted/quarantined records, drains writers with a bounded wait,
  verifies ciphertext removal and cleans a late completion again after timeout.
  Rollback cannot restore a pre-wipe snapshot. Policy lifecycles are destroyed
  only after actual OS-key deletion succeeds; partial failure stays suspended.
  New durable adapter instances remain blocked until process restart.

These changes introduce no network, model, telemetry, background capture, new
memory classes, plaintext migration, or external action path.

## Reproduction and integration scope

```sh
flutter pub get --enforce-lockfile
flutter test --no-pub --reporter expanded --concurrency 2 --timeout 2m \
  test/core test/encrypted_memory test/data_wipe*test.dart
flutter analyze --fatal-infos \
  lib/core/memory lib/encrypted_memory lib/src/core/data_wipe_service.dart \
  test/core test/encrypted_memory test/data_wipe_memory_contracts_test.dart \
  test/helpers/data_wipe_fixture.dart
```

[Memory release-contract CI](../.github/workflows/neura-memory-release-contracts.yml)
runs the current source and a separate disposable integration with the exact
#133 commit above. It records the review head, base, checkout commit, actual
staged test tree, integration diff and expanded test log. Neither lane merges a
PR or pushes source changes.

The integration also applies the tracked
[`pr133-terminal-key-revocation.patch`](../test/fixtures/pr133-terminal-key-revocation.patch).
It tightens one old #133 assertion from a later authentication `Exception` to
immediate `StateError` for a destroyed handle. This is an explicit test adaptation
in the disposable checkout; #133 itself remains unchanged. Its
[`DataWipeFixture`](../test/helpers/data_wipe_fixture.dart) is reused unchanged.
`path` is declared as a direct development dependency, at its existing locked
version, to analyze that reused fixture without suppressions.

## Validation record

Final review-head validation is pending. Update this section with exact run,
head and tested-tree references after the focused jobs finish.

Historical #133 evidence remains distinct:
[38606990921, attempt 3](https://github.com/Vantiger-Construction/neura_os/actions/runs/38606990921/attempts/3)
passed 19 focused wipe tests and 121 related tests. Its job logs checked out
`e0ba4cb1af12d11c606f093e124557e2cb47a5f7`, an older synthetic merge; this is not a
pass for the current default or the newly combined source. That execution was
October 17 UTC and was reconciled on October 18.

## Remaining release requirements

1. Review and integrate the intended final code through normal PR/security
   gates, then validate that exact combined tree. A focused candidate-integration
   pass does not merge #133, transfer its CodeQL result, or certify every app
   workflow. Re-run if either candidate or the default changes materially.
2. Complete the scoped memory runtime design: map admitted data classes and
   actual read/write entry points to consent, clear the RAM-only session seam
   through its owner, and verify actual rotation/selected export if shipped.
   Existing legacy chat/journal behavior cannot be called foundation compliance.
3. Define and verify crash/restart handling for an incomplete full wipe. These
   regressions prove same-process suspension, failed deletion and retry; they do
   not establish a persistent wipe-intent/recovery protocol after process death.
4. Validate legacy-key migration, OS credential-store unavailable/locked states,
   successful key deletion/readback and stale ciphertext rejection across actual
   process restarts on supported Windows and Android devices.
5. On dedicated synthetic app profiles, verify device-level failed deletion,
   interruption/retry, concurrent read/write/wipe, Safe Mode mic-off, storage
   failure and no plaintext payload/new key in files, preferences, backups or
   diagnostics. Record exact installer/APK hash, app commit, OS/device, procedure
   and observed result. Never use a user's real journal as a wipe fixture.

No Windows/Android physical result or public-release approval is recorded here.
