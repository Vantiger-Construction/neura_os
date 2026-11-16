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
written. The contract rejects a candidate compared with itself, including a
byte-identical copy at another path.

The manual Windows workflow builds the existing tested Neura package and then
verifies the ZIP produced by that build. Set `previous_windows_asset_id` to the
numeric release asset ID of the Windows ZIP your users would update from. The
workflow retrieves that asset from this repository and checks its published SHA-256
before rehearsal. The previous ZIP may contain a flat Windows bundle or an
`app/` folder. The receipt identifies both payload inventories. Use an empty
output directory for each local invocation. The release operator must leave Authenticode enforcement
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

## Android in-place upgrade preflight

Use verified copies of the previous and proposed APKs, Python 3.11 or newer,
Java, and Android SDK Build Tools. This command reads both files without
installing either. Use the APK pulled from the existing device to check that
particular installation.

```sh
python tools/release/check_android_update.py --build-tools /path/to/build-tools/36.0.0 previous.apk candidate.apk
```

Exit code 0 confirms valid signatures, matching Neura app IDs and signer sets,
and an increasing version code. Exit code 1 identifies an upgrade blocker.
Exit code 2 means inspection failed. A rotated production signing lineage
requires separate platform verification. Physical startup, data preservation
and rollback require their own device evidence. Preserve an existing installation
when the signer comparison fails.
