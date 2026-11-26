# Legacy vault ZIP reliability

This correction is independent of dependency PR #261. It is based on Neura
`ed8fa75a4b5d22370fa9f71a793f57cd331f2c2f` and keeps the application lockfile
unchanged. No repository setting, cloud processing, model download, native
installation or actual user memory is part of implementation/testing.

## Before and after

Previously a malformed later capsule or attachment-write failure could leave
earlier JSON records in the vault. Duplicate IDs skipped the JSON but admitted
new attachments. Corrupt ZIP checksums were not verified. Missing attachments
and failed body decryption could silently change what a purported complete or
decrypted export contained.

Both dependency versions now use the same bounded, strict import path:

1. Stream input with a compressed byte budget. Before decoder allocation,
   validate classic ZIP directory boundaries, counts, sizes, compression methods,
   local data extents, matching local/directory headers and raw duplicate names.
   Reject split, ZIP64, ZIP-level
   encrypted and unsupported-compression inputs explicitly.
2. Verify ZIP errors and CRCs; canonicalize EOCD comment/trailing metadata after
   validating its real directory. This also avoids 4.6.0's false EOCD-in-comment
   selection. Member bytes, offsets and checksums remain unchanged.
3. Parse every capsule, validate crypto field shape without decrypting raw
   imports, and bind each safe attachment reference to an exact ZIP entry.
   Refuse missing/orphan files, links, traversal, unsafe Windows names, case
   collisions, duplicate IDs and nested paths that would otherwise flatten.
4. Validate the optional versioned SHA-256 inventory manifest. Old whole-vault
   exports without a manifest remain readable. This inventory is not an
   authenticity signature: an attacker able to replace a ZIP can replace its
   manifest too. Capsule AES-GCM still authenticates its encrypted body.
5. Skip existing IDs with all related attachments. Refuse occupied orphan
   destinations. Stage only new capsules, flush and verify written bytes, then
   persist an ownership journal before moving any final destinations.
6. Move complete attachment directories, then capsule JSON; verify final hashes
   before writing the commit marker. Before the next public read/write, recover
   any interrupted operation. Uncommitted, unchanged operation-owned data is
   rolled back; committed data is retained and cleanup resumed. Unexpected
   files or changed hashes block recovery for review and are never deleted as
   collateral cleanup.

The in-process queue gates reads and writes while an import commits/recovers.
A file lock coordinates cooperating processes. Multi-file filesystem rename is
not globally atomic, and unrelated external writers are outside this protocol.
The service must be used to read restored records. Native Windows filesystem
semantics and actual process-death behavior still need device acceptance.

## Wipe and failure behavior

Full data wipe closes legacy admission synchronously, invalidates late picker
results, and drains imports/exports and any rollback before deleting app files.
It stays closed for the process lifetime. Scoped legacy deletion similarly
invalidates older work, waits for it, deletes, then permits fresh requests.
Cooperating-process locks do not make a separate, uncoordinated process's wipe
safe; close other Neura processes during physical restore/deletion acceptance.

Import failure never reports success while partially committed records remain
available through the service. Failed rollback keeps its journal and blocks
reads until verified recovery can complete. Unknown data is preserved. A
successful commit may report `cleanupPending`; its verified data is retained,
and the next access retries temporary cleanup. The operation lock is harmless
bookkeeping and may exist after a rejected request; rejected requests do not
leave new capsule or attachment content.

If a write reports an error after a valid commit marker reached disk, recovery
verifies the complete committed inventory and reports the retained import.
Corrupted marker writes instead trigger rollback. Unprepared staging names
cannot publish capsules; an owned unprepared stage can be cleaned on restart,
while unknown staging data is preserved.

New exports include an optional inventory manifest, are strictly decoded before
writing, written to a unique `.partial`, reread/hash-verified, then promoted.
Failure removes only that operation's partial output and leaves prior exports
intact. Full wipe also recognizes interrupted ZIP `.partial` files. Whole-vault
exports reject corrupted capsule records and missing/unreadable attachments
rather than claiming completeness. The PDF cover remains optional; attachment
omissions are never silently accepted in delivery packets.

Correct decryption explicitly clears all four nullable crypto fields. Incorrect
passphrases preserve encrypted content and return an accurate encrypted count;
both export screens use that result. Packet README text states actual body
encryption and that attachments/metadata are readable. JSON export remains a
separate, explicitly decrypted format.

## Current in-memory limits

| Budget | Default |
| --- | --- |
| Compressed input/output ZIP | 128 MiB |
| One uncompressed member/attachment | 64 MiB |
| Aggregate uncompressed members | 128 MiB |
| One capsule JSON / inventory manifest | 1 MiB |
| ZIP directory entries | 4,096 |
| Capsule records | 512 |

These are conservative refusal limits, not measured Windows acceptance values.
They are explicit errors, never silent truncation. Older larger archives, ZIP64,
or non-flat attachment layouts require a separately reviewed restore route;
this code must not silently increase limits to admit them. Constructor limits
also allow smaller synthetic boundary fixtures without allocating large files.

Input is streamed with a bound, but encoding/decoding and admitted attachments
still use memory buffers. Do not infer RAM needs from compressed size alone.
On the approximately 8 GB Windows target, measure whole-application RAM, available
RAM, paging, UI latency and disk headroom with 16/64 MiB fictional attachments
before considering 128 MiB or many-small-entry acceptance. Do not automatically
start/download a model. The previous review's Linux samples are historical,
not measurements of this corrected implementation or the physical laptop.

## Reproduce synthetic validation

Use the exact Flutter version in `.github/workflows/neura-coverage.yml`.

```sh
flutter pub get --enforce-lockfile
flutter test --no-pub --concurrency 2 --timeout 2m test/legacy
python3 tools/archive_compatibility/run_matrix.py
flutter analyze --fatal-infos
flutter test --no-pub --concurrency 2 --timeout 2m
```

The matrix resolves exact archive 4.6.0 and 4.7.1 package archives into a fresh
temporary cache, verifies their known SHA-256 hashes, substitutes only archive
in copies of package_config, and leaves the application lockfile unchanged.
It runs the regression suite under each reader version, produces fresh raw,
decrypted and fallback exports under each version, then performs all four
producer/reader combinations. Original and new evidence remain separate.

Results/logs and the six fresh ZIPs go to a fresh
`build/legacy-zip-compatibility` directory (or `--output`); no installed Neura
store, microphone, cloud service or actual encrypted memories are used. The
fresh classic ZIP layout remains readable by older vault importers, which ignore
the optional manifest. Historical 4.6.0 behavior with arbitrary commented ZIPs
is not reclassified as compatible by these tests.

Hosted matrix success, native Windows/Android package success and physical-device
acceptance are distinct. Keep actual Windows/Android installation, picker URI,
filesystem and RAM observations NOT RUN until observed on isolated fictional
workspaces. This correction does not authorize a PR merge or app update.
