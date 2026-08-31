# Neura release readiness 1.5.2

This gate is stacked after PR #49 and does not change Safe Mode, Recovery,
Living Intelligence, consent-scoped inference, Fresh Approval, or Action Loom.

## Gate contract

A release candidate fails closed unless it:

- contains the required Windows executable, Flutter runtime, ICU data, and app snapshot;
- produces a deterministic per-file SHA-256 inventory and JSON manifest;
- survives immediate checksum re-verification;
- passes an isolated A/B upgrade staging and rollback rehearsal;
- has valid Authenticode on every executable and DLL when release signing is required;
- matches the configured certificate publisher when a publisher is supplied.

The rehearsal copies payloads only into a temporary output tree. It never
installs, launches, replaces, or deletes a user's current Neura installation.

## Validation modes

Pull requests run the portable contract tests. They prove complete payloads
pass, incomplete payloads fail closed, and the upgrade/rollback evidence is
written.

The manual Windows workflow builds the existing tested Neura package and then
runs the full verifier. The release operator must leave Authenticode enforcement
enabled for production candidates. Development verification may explicitly
disable it, but its manifest is marked `development-not-required` and must not
be represented as production-signed.

## Evidence

Successful runs publish:

- `RELEASE_MANIFEST.json`
- `SHA256SUMS.txt`
- `ROLLBACK_REHEARSAL.json`
- the existing packaged ZIP

Production certificate material stays outside the repository and artifacts.
