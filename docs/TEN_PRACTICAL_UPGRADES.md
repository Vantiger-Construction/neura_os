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
- No dependencies, native platform code, model downloads, provider permissions,
  microphone behavior, or automatic memory collection change. Existing backup
  encryption and duplicate handling remain in use.

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
existing entries survive conflicts. This change does not publish an app release.
