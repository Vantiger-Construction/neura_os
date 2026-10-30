# Encrypted-memory release-contract evidence

## Current review stack — October 30, 2026

Review and merge the dependency-ordered replacement PRs #151 (foundation),
#152 (scoped owner) and #153 (application integration). PR #141 remains an
unmerged aggregate reference. Each successor must target Neura and pass fresh
applicable checks and independent review after its predecessor lands.

The initial extraction reproduced #141 head `84f0ea61` byte for byte. Subsequent
review corrections strengthen that candidate while keeping all earlier regression
coverage and security policies:

- Durable crypto authorities require verified OS-backed keys; the legacy key
  fallback remains available only to its separate journal-recovery path.
- Availability is checked before synchronous owner reservation. Failed first-use
  admission releases an unverified empty reservation; pending work, ambiguous
  writes, established authorities and terminal wipe suspension keep ownership.
- Full wipe removes and verifies the default scoped envelope before device-key
  destruction even when no scoped owner was created in the current process.
- The 100-note limit is rechecked inside the shared serialized write. Concurrent
  callers cannot both pass an earlier service-level count and exceed the cap.
- System instructions never contain recalled note contents. A fresh prompt grant
  recalls bounded notes into a separately labeled JSON payload in a user-role
  message. The exact cloud preview, sensitive-local policy, cancellation and
  lifetime checks still apply. Default, private-room and offline exclusions remain.
- Note entry and reviewed-note search request disabled personalized IME learning.
  Actual keyboard behavior remains part of physical Android acceptance.

Five controlled tests fail on the original foundation and pass after correction;
additional regressions verify atomic capacity, concurrent owners, note/message
roles, instruction-like note data and input privacy flags. Existing post-AES
JSON generation checks and successful Uint8List test compilation were verified
in the complete source rather than changed in response to diff-only findings.

The PR descriptions record the immutable current heads, tested trees, counts and
remaining CI/review gates. The dated sections below are historical evidence;
references to recalled notes in system prompts describe the earlier candidate.
In-process wipe guarantees remain distinct from the outstanding durable recovery
protocol and physical restart/key-store/microphone acceptance. No public release
or physical acceptance is implied.

This is an engineering verification record for the existing P1 task
[Validate encrypted memory release contracts](https://app.notion.com/p/3f4cff6b3f43818eb64ae3946aea4c31).
Synthetic automated validation does not complete physical-device acceptance or
approve a public release. PR #133 and this review branch require human review.

## Production consent integration — October 21, 2026

Implementation and tests: `2927656e3b0ec71b4b8f4a28ff3c73f7c6ace5c9`,
tree `107953058d26e9337f7c0bb6d50d8e9490228d88`, based on the existing #141
head `1459d13bff73e6305088fc2e5cf073edbfe0084f`. Later edits to this evidence
file do not change those code/test inputs. This candidate stays draft.

### Actual authorization paths

| Entry point | Earlier effective authorization and gap | Integrated behavior |
| --- | --- | --- |
| Chat `NeuraChatScreen` → `NeuraAiService.streamReply` | Private-room restrictions, next-reply opt-in, private-context tracking, cancellation and separate cloud approval were effective. A room's `persistMemory` flag was not a lease; ordinary turns were automatically logged. | A direct checkbox gesture creates a prompt-destination, single-use recall grant. Send transfers it to exactly that turn. Raw user/reply logging is removed, receipts report no automatic long-term save, and visible working history remains available. |
| `NeuraPromptBuilder.buildSystemMessage` | AI chat callers supplied a room/opt-in boolean, and summaries explicitly passed false. The builder itself defaulted true and read the legacy graph/profile without foundation consent. | Defaults false; a boolean alone never reads memory. A valid prompt permission recalls only admitted notes through the scoped owner. Legacy/profile reads are removed. Notes are marked untrusted context, not action authority. |
| `MemoryScreen` | Opening the route automatically decrypted up to 500 mixed legacy nodes. Clear had an explicit confirmation. | Opening performs no memory I/O. Review requires its own grant, search uses that authorized RAM result, and Remember persists only text explicitly entered as a companion note. Review is not prompt consent. Confirmed clear removes scoped notes plus legacy history/profile while preserving journal stores. |
| Therapy reflection save | Explicit Save authorized the encrypted local reflection store, but also copied raw text into the graph without a separate memory lease. | The encrypted reflection save/history workflow remains; the companion-memory copy is removed. |
| Mirror check-in | Done saved mood and raw reflection into the graph without a memory lease. | An explicit Save check-in locally control saves the reflection to the existing encrypted local reflection journal. Mood presentation remains; save failure retains the draft. No raw graph copy is made. |
| Typed/voice journal screens → `LocalJournalStore` | Explicit saves, durable confirmation, draft retention and revision/conflict behavior already belonged to the local journal. | Unchanged local authority and storage behavior. No automatic conversion into a scoped memory class; sync remains separate. |
| Wake-word reply path | Voice opt-in/Safe Mode/cancellation protected capture; these were not memory consent. Cloud requests without a visible approval handler already failed closed. | Automatic raw chat-memory copies are removed. Voice commands cannot create memory grants; exclude-memories revokes an existing one, and unrelated context commands preserve the user's pending selection. |
| App-open consolidation | Fresh-cloud approval prevented unattended cloud submission, but the hook still attempted unscoped local graph recall. | The app-open hook and prompt's legacy profile read are removed. The old class is retained for compatibility/wipe cleanup and has no current production recall caller. |

`CompanionMemoryService` is the production owner. It constructs the existing
durable adapter only when an explicit memory control is used, after verifying
an OS-backed key. A random non-secret local-profile identifier scopes owner and
device; it is not hardware identification or a cloud account identity. Missing
identity alongside existing scoped ciphertext fails closed instead of adopting
old data. A preference-backed legacy-key fallback can still serve existing
journal recovery, but cannot back new production companion notes.

The single admitted production scope is user-authored note / direct local user /
personal sensitivity / companion-notes capsule. Notes are independently entered
in the memory screen, never automatically derived from chats or journals. Values
are bounded to 1,000 characters, scope review returns a newest-first tail of at
most 100 records, and prompts include at most eight notes. Payloads/provenance
remain AES-GCM ciphertext in the existing local envelope. No background collection, sync,
model or cloud call is added by the memory owner.

Every permission is transient, destination-bound, single-use and five minutes
long (within the existing 15-minute maximum). Scope/operation/owner and current
lifetime are checked before I/O, after restore and at persistence boundaries.
Revocation remains effective after consumption for outstanding asynchronous work.
Expiry, background, Safe Mode/recovery, screen disposal, active chat cancellation,
explicit exclusion and full wipe invalidate the relevant permissions. Full wipe
also suspends the production owners synchronously and reuses #141's registry
cache clearing, bounded drain and late-write cleanup.

Cloud authorization stays independent: the existing sensitive-content-local
constitution still blocks memory-bearing cloud requests by default. If the user
has separately permitted that category, each exact request still needs fresh
preview approval. Permission is rechecked before/after that preview and during
streaming; expiry/revocation prevents a pending submission. Model-generated
instructions cannot create or widen a grant.

A native write already issued under valid consent cannot be recalled. If consent
expires or is revoked before completion, the caller receives no success and the
adapter requires reconciliation; encrypted bytes may have reached storage. A
fresh, separately authorized review can reconcile them. Revocation is not a
promise to erase an already-admitted native write; explicit scoped/full wipe has
its own verified deletion contract.

Persona/current-mood presentation settings, local safety checks, recap analytics,
joy metrics and proactivity outcome metadata remain independent feature stores
or legacy graph users. They are not represented as compliant scoped-note memory.
No raw-history migration, automatic collection or change to those permissions is
implied. Physical-device acceptance, key-store/restart recovery and the broader
release requirements below remain open.

### New regression evidence

The 33 new integration cases use synthetic fixtures, real AES-GCM and mocked OS
stores. Tests cover absent/expired/revoked/pre-issue permissions, exact scope and
destination mismatches, replay, bounded ordering, cold restore, revoked native
completion, Safe Mode/recovery/background, route disposal, idle expiry, actual
full-wipe orchestration, production local-owner provisioning, local journal and
encrypted reflection preservation, and fresh cloud approval/cancellation. No real
journal, microphone, model, credential or external network is used as a fixture.

| Local validation on Flutter 3.47.5 / Dart 3.13.4, Linux | Confirmed result |
| --- | --- |
| Complete current-source Flutter suite | 906 passed |
| Complete Flutter suite with current #133 head `258ff87` | 924 passed |
| Expanded current-source memory/journal/prompt/router/voice-command suite | 182 passed |
| Same expanded suite with current #133 head `258ff87` | 200 passed |
| Strict analysis | Current source and combined source: no issues |
| Canonical formatting | Current source: 36 files, zero changes; combined: 42 files, zero changes |

The current-source tree is `107953058d26e9337f7c0bb6d50d8e9490228d88`.
The disposable combined tree is `3adef3fac0fb1eae772b4972281c5b0401ba069b`.
Only the known add/add fixture conflict was resolved, after verifying ours
`383624734a80fa3716b8b3b9fee0cf49390aa49d` and theirs
`d4f533ee6905694296ae8124947f2bca8f98b467`. The tracked terminal-key assertion
adaptation was applied to the disposable index. #133's branch was not edited.
The 182 tests are included in the 200; these are not 382 distinct tests.

Reproduction uses locked dependencies, `flutter test --no-pub --reporter expanded --concurrency 2 --timeout 2m` for the complete suite, and the explicit expanded
file list in the updated memory-release workflow for each focused lane. That
workflow now covers the production owners, journal preservation and voice-command
regression, and pins the current #133 commit. Local test results do not transfer
older hosted/CodeQL/Windows/Android statuses to this new head. Required hosted
checks and physical-device acceptance remain separate pending gates.

No physical Windows/Android result or merge approval is inferred from these tests.

## Source boundaries

- Reviewed default: [`08fd9493038ef2aa6274c3a12402d96299b5b1bb`](https://github.com/Vantiger-Construction/neura_os/commit/08fd9493038ef2aa6274c3a12402d96299b5b1bb).
- Merged history work: [PR #113](https://github.com/Vantiger-Construction/neura_os/pull/113),
  merge [`5395a0457b51f0d1da048b6526680d12218615f3`](https://github.com/Vantiger-Construction/neura_os/commit/5395a0457b51f0d1da048b6526680d12218615f3).
  Its graph, tail helper and graph tests are unchanged in the reviewed default.
- Historical wipe-candidate pin: [PR #133](https://github.com/Vantiger-Construction/neura_os/pull/133),
  [`b822c48be5a871d5a5e8e88825205d70534216d0`](https://github.com/Vantiger-Construction/neura_os/commit/b822c48be5a871d5a5e8e88825205d70534216d0).
- Current #133 head and new CI integration pin: `258ff8785e85882c5905eaded85969b93db48544`.
  This merges current default `08fd949` into prior head `d7ca911`. The earlier
  `b822c48` / `d7ca911` pins below belong to historical validation; the new local
  combined validation uses `258ff87` directly. Neither PR was merged.
- Corrections and new regressions: [draft PR #141](https://github.com/Vantiger-Construction/neura_os/pull/141).

The legacy JSONL graph, RAM-only session seam and durable scoped envelope remain
separate implementations. The production `CompanionMemoryService` now owns the
durable adapter for explicitly authored companion notes. It never imports or
relabels raw chat, journals, therapy, mood notes or the old consolidated profile.
Legacy graph analytics remain separate APIs without foundation leases; they are
not a source for companion prompts or the companion-memory review screen.

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

## Historical component validation record

[Run 39234170927](https://github.com/Vantiger-Construction/neura_os/actions/runs/39234170927)
passed both lanes on reviewed code/test head
`596a91a1667903f3e331db69e89053d27d4a6d6b`, default base `08fd9493038ef2aa6274c3a12402d96299b5b1bb`.
Both jobs checked out PR merge `16fedc1dd8bb753b35ecf86bfeb7955c30e6c1da`.

| Lane | Result | Actual tested tree | Evidence |
| --- | --- | --- | --- |
| Current application source | 63 focused tests passed; strict analysis clean; canonical formatting changed zero of 21 files | `30d33313a140787b423fd637aef604957c8aa02d`, exactly the reviewed head tree | [Job 117999122426](https://github.com/Vantiger-Construction/neura_os/actions/runs/39234170927/job/117999122426), [artifact 12178398656](https://github.com/Vantiger-Construction/neura_os/actions/runs/39234170927/artifacts/12178398656) |
| Source plus pinned #133 and the explicit assertion adaptation | 81 focused tests passed; strict analysis clean; canonical formatting changed zero of 21 files | `1c7a5b8f88b0a0412b7bc5828c0ffe542edf20a9`, independently reproduced locally | [Job 117999122975](https://github.com/Vantiger-Construction/neura_os/actions/runs/39234170927/job/117999122975), [artifact 12178283675](https://github.com/Vantiger-Construction/neura_os/actions/runs/39234170927/artifacts/12178283675) |

The counts overlap: 63 is a subset of 81, not 144 distinct tests. This branch
adds 17 focused regression cases. Both downloaded evidence ZIPs were checked
against GitHub's SHA-256 digests, and their head/base/checkout/tree/test-log
contents match the identities above:

- Current ZIP: `498e4c390c06bca3bcbcf1ce77370377b34154b394c8208c319f480147c27ebf`.
- Combined ZIP: `54b4df5e83eb9e56cf2f9cfea3dbde9a1437d9c4be07c2b2048754a19853f38f`.

The artifacts expire on November 2, 2026; this record, the source commits and
test names preserve the reproducible result. Subsequent evidence-only edits to
this document do not alter the validated code, tests, dependency locks or CI.
Complete-suite, Windows/Android packaging and other PR gates remain separately
scoped; this focused record does not imply they all passed.

PR #133's newer [CodeQL Code Quality run 39232230353](https://github.com/Vantiger-Construction/neura_os/actions/runs/39232230353)
also passed both language jobs on `d7ca911`. This supersedes its older failed
Code Quality status; it is neither #141 validation nor Code Security clearance.

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
2. Review and physically accept the production companion-note path below.
   Independent legacy analytics and persona/current-mood settings are not scoped
   note records and are not certified by this integration. The unused RAM-only
   session seam still needs an owner if activated. Verify actual rotation and
   selected export if shipped; raw journal/history migration is not authorized.
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

## October 22 PR repair checkpoint

Integrated default branch `889edf5` (merged engine, launcher, Ollama and full-wipe
work) into this draft. The only merge conflict was the previously documented
shared wipe fixture. Retained the complete PR fixture, including all preference
hooks; applied the tracked terminal-key assertion adaptation to the now-merged
lifecycle regression. Successful wipe cannot revive an old crypto handle.

PR #133 is now on the default branch. Its wipe tests run directly alongside
consent-memory tests; the redundant synthetic PR #133 merge lane is retired.
The tests and completeness/consent gates remain enabled. Previous two-lane
results above describe their original source, not this repair.

Also carried the four reviewed security lock repairs from PR #143: quinn-proto
0.11.18, rustls 0.23.46, rustls-webpki 0.103.16 and webpki-roots 1.0.10.
No other locked versions changed. Current combined-source tests must be
recorded before release acceptance; keep this PR draft and unmerged.
