# Ten practical Neura upgrades

This change extends the current app's planner, selected-document reference shelf,
and encrypted vault backups. It is based on `Neura` commit
`f03c5196cb610b04b703553ee15ad5154ab3b3cf`.

| # | Upgrade | Where and how to use it |
| --- | --- | --- |
| 1 | Local plan templates | In **Plan my day**, choose **Gentle start**, **Focus session**, or **Evening reset**. Replacing an existing draft requires confirmation. Preview and approve the resulting plan yourself. |
| 2 | Edit one plan step | Open a step's options and choose **Edit step**. Other steps keep their progress; an edited step becomes unfinished. |
| 3 | Add or remove steps | Use **Add a step**, or **Remove step** in a step's options. Plans remain limited to 1–8 steps of up to 160 characters each. |
| 4 | Reorder a plan | Use **Move up** or **Move down** in a step's options. Completion follows the step when it moves. |
| 5 | Undo a plan edit | **Undo last edit** restores one structural change and its prior progress. It never restores approval, and new recorded progress clears the old undo. |
| 6 | Focus on the next step | After approving the plan, enable **Focus on next step**. Only the next unfinished step appears. Checking it yourself advances the view. |
| 7 | Exact phrase search | On the reference shelf, choose **Exact phrase** to find a literal, case-insensitive phrase in the document you selected. Punctuation is treated literally. |
| 8 | Read source context | Expand **Read surrounding lines** under a match to inspect up to two lines before and after it, with source line numbers. |
| 9 | Verify an encrypted backup | In Memory Vault, choose **Verify or restore encrypted backup**, select a `.neurabackup` file, enter its passphrase, and choose **Verify without importing**. This checks decryption and every record without reading or writing live vault entries. |
| 10 | Restore selected entries | After verification, review entry titles and dates, choose entries, and confirm **Restore selected**. Nothing is selected automatically. Identical entries are skipped and conflicting versions are preserved separately. |

## Boundaries

- Structural plan edits require fresh **Use this plan** approval. Templates and
  focus mode never run tasks automatically. The plan, draft, and undo stay in RAM
  and clear on background, Safe Mode, recovery, or screen disposal.
- Searching and reading context happen locally. Expanded surrounding lines do
  not enter a model request. The existing explicit permission still covers only
  the displayed matching passages, with the existing size and revocation limits.
- Backup selection reads ciphertext only and is limited to 25 MB. The native
  picker may finish its foreground round trip before the passphrase is entered.
  Verification, passphrases, selections, and decrypted reviews clear on
  background, Safe Mode, recovery, or disposal; late results cannot recreate them.
- A restore review can authorize one write only. Clearing a review revokes a
  pending confirmation and blocks overlapping operations while a previously
  confirmed write finishes. Clear does not undo a write that has already begun.
- The original PR did not change dependencies, native platform code, model
  downloads, provider permissions, microphone behavior, or automatic memory
  collection. The follow-up dependency correction is documented below. Existing
  backup encryption and duplicate handling remain in use.

## Validation and acceptance

The implementation includes model and widget regressions for progress mapping,
undo and approval, template replacement, focus mode, phrase matching, local-only
source context, immutable one-use restore reviews, selected restores, interrupted
decryption, picker lifecycle, revoked confirmations, and overlapping writes.
Fixtures contain synthetic data only.

The PR records the tested tree, tool versions, and command results. Flutter
widget lifecycle tests simulate platform events; they do not establish physical
Windows or Android picker behavior. Before release, exercise the three screens
on each supported target, including large text, native file selection, background
and resume, Safe Mode, wrong passphrases, and selective restore from a disposable
synthetic vault. Check that unselected entries are never imported and that
existing entries survive conflicts. Automated preview packaging does not
establish public-release acceptance.


## November 6 safety review and follow-up

PR #175 merged as `90de867221a325f3e95b61c2c592ae3df5604907`. Its 25 successful
checks and four skipped checks did not prove preservation under failed vault
reads or concurrent writes. Three new tests reproduced overwritten unreadable
ciphertext, a lost entry from concurrent restores, and wipe completing before
an admitted restore. The follow-up serializes vault reads/migrations and
mutations, refuses unreadable or malformed live data, checks the current PIN,
and rechecks a revocable restore permit before the final data write. Wipe
revokes queued operations and drains admitted work before deleting and verifying
storage. Full-data wipe closes admission synchronously until restart. The unused
all-entry import API has been removed; callers must select entries explicitly.

Cancellation, background, Safe Mode, clear, or disposal can revoke a pending
restore before storage admission. A platform write already admitted cannot be
retracted; a subsequent wipe waits for it and then removes its result. Do not
interpret closing a screen as undoing an already committed restore.

The dependency has returned to exact `flutter_secure_storage` **10.3.4**. The
[upstream v11 removal notice](https://pub.dev/packages/flutter_secure_storage/changelog)
requires v10 migration of existing v9 ciphers; the
[10.3.4 changelog](https://pub.dev/packages/flutter_secure_storage/versions/10.3.4/changelog)
also includes migration/data-preservation fixes beyond the original 10.3.1
pin. `resetOnError: false`, migration backup, existing namespaces and key names,
and encrypted record formats remain unchanged. The solver also selects Darwin
0.3.2, which is the v10-compatible line; Windows remains 4.2.2. Dependabot major
proposals for this package are held, and a security regression rejects silently
skipping the migration stage. This change cannot recover keys already lost by
an earlier installation.

Before distributing an upgrade, use disposable synthetic vaults to verify:

- Android v9 to this v10 build, including skipped app versions; all original
  keys and encrypted memories must remain readable without resetting storage.
- Already migrated v10 and v11 preview installations to this candidate; compare
  all keys and records, reboot, and repeat unlock/restore. Do not test a downgrade
  against the only copy of real memories.
- Windows existing-install upgrade and native file picker; Android picker,
  background/resume, Safe Mode, cancellation during restore, and selective
  duplicate/conflict handling.
- Full-data wipe during a blocked write, followed by restart and verified
  absence of old keys, entries and late recreated data.

Automated fixtures and package builds are separate from this installed-device
acceptance. Independent GitHub review was requested; the configured Claude
workflow failed before review because provider authentication was absent.
A follow-up must remain unmerged until review and its applicable current-head
checks are complete. CI preview artifacts are not public-release acceptance.


Local follow-up validation with Flutter 3.47.9 / Dart 3.13.7: all 1,313 Flutter
tests passed; committed-policy strict analysis and formatting passed; 17 source
composition and 11 security regressions passed; Actionlint 1.7.12 passed.
OSV-Scanner 2.7.0 reported no known findings across the exact 225 Pub, 228 Cargo,
and one npm locked package. Native Windows/Android and hosted integration
results must be recorded against the follow-up head, not borrowed from #175.

### Independent review corrections

Sourcery's November 6 review identified eight further failure paths. Scheduled
backups now close admission synchronously at full-data wipe and all active
instances drain before app-support deletion. A cancelled backup cannot record
a late outcome or submit a new file write. Already submitted platform/file
writes must finish before deletion can be confirmed.

Vault deletion checks removal results and reloads platform preferences before
verifying absence, including the legacy PIN and pending PIN-change record.
If storage does not respond within 30 seconds, wipe reports an incomplete
operation. Its underlying queue stays closed and continues waiting to delete
any late write; retry may confirm completion. A timeout does not cancel a
platform write or establish successful deletion. Full-data wipe retains its
process-wide suspension until restart.

PIN setup and data writes check platform results and read back durable values.
PIN changes preserve the old encrypted data and verifier in the temporary
`neura.vault.pinChange.v1` preference; it contains ciphertext, never the PIN or
decrypted entries. Both replacements must verify before the rollback record is
removed. Failed/interrupted changes restore the previous pair before the next
vault operation; a failed rollback retains its record for recovery on a later
unlock/restart. Full-data wipe removes this recovery record too. Existing
encryption keys and ciphertext formats are preserved.

New vault IDs are checked against existing entries even if multiple additions
share a timestamp. Older entries may omit optional tags; malformed supplied
tags and required fields still fail closed. Coach saves now surface storage
errors instead of leaving an unhandled asynchronous error.

Before release, add failed PIN setup/change/rollback, process restart during a
PIN change, durable deletion failure, same-clock additions, and wipe during a
scheduled backup to the disposable-vault device checks. Independent review and
current-head CI remain required; implementing review comments is not approval.

The next independent review also covered manual exports, scheduled-backup
settings and overlapping runs. All backup file writes, including an admitted
native save dialog, now join the wipe drain. Settings mutations close admission
at wipe start and drain before passphrase deletion and durable preference
verification. If either drain times out, full-data wipe stops before deleting
their destinations, reports incomplete removal, and keeps admission closed.
Finish/cancel the native dialog or wait for storage, then retry the wipe. A
timeout never permits a late writer to race deletion. Previously exported
user-owned copies still require separate deletion by their owner.

Scheduled runs share a queue across service instances, including their due
check and file replacement. Add/delete validate the PIN even for an empty
vault. Existing duplicate IDs from the older timestamp generator receive stable,
non-conflicting IDs in memory without losing entries; the next explicit mutation
persists those IDs. Required-field corruption still fails closed.
