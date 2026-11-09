## Problem and resulting behavior

Describe the concrete trigger, before/after behavior and relevant issue.

## Validation

Record commands and results for the exact head or tested integration tree.
Distinguish local checks, hosted checks, native builds and physical-device tests.
State what could not be tested and why.

## Compatibility and privacy

Describe effects on consent, microphone lifecycle, encrypted data, wipe, local
journals, offline limits, dependency migration or rollback. Write "Not affected"
when appropriate. Use synthetic examples and redacted evidence.

## Review notes

- [ ] The change has a focused scope and preserves unrelated work.
- [ ] Relevant checks pass, or remaining failures are explained.
- [ ] Dependencies, generated files and platform changes are intentional.
- [ ] Remaining release/device acceptance is stated without claiming it passed.

## Stabilization candidate

For changes in the Windows-first acceptance cycle:

- Record the reproduced first failure and the single behavior being repaired.
- Pin the candidate head, actual packaged commit/tree, archive and executable hashes.
- Keep existing SDK/model admission and consent boundaries; identify any deliberate change.
- Separate synthetic CI, native packaging, operator observations and independent acceptance.
- Keep Windows and Samsung results separate; retain NOT RUN/BLOCKED where appropriate.
- Attach only inspected, redacted evidence. No private audio, chat, journals or credentials.

Use [Windows-first acceptance](../docs/WINDOWS_FIRST_ACCEPTANCE.md) for the
10-minute conversation, practical plan, local journal and scoped-memory checks.

