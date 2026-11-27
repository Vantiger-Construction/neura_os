# Fictional legacy ZIP compatibility fixtures

All 44 ZIP files are fictional. They were frozen from the November 26, 2026
Neura PR #261 review kit, before the implementation in this branch.

- Service/model source: `a0ca21c87a3b3713934b6e307cd98ae8dbda1eea`.
- Source tree: `e0e705f5b11d2685e32896b0bd36a731690da017`.
- Original kit SHA-256: `f84bcbc4aee29d1c699203baeccc668acf5f69d71646015aed712a447d69b8b1`.
- Producer dependencies: archive 4.6.0 / 4.7.1 and cryptography 2.9.0.
- Original producer runtime: standalone Dart 3.14.1 on Linux, with test path,
  picker and PDF collaborators. Current regression tests run the branch-pinned
  Flutter SDK and actual production service/codec; these are different scopes.
- Fictional passphrase: `Fictional Archive Kit Only 2026!`.
- Fictional decrypted body: `Fictional Rowan saved a note about a blue paper moon.`

Each version folder has the original per-file SHA-256 manifest. It contains
six actual service exports (whole-vault and delivery packet in raw, decrypted
and wrong-passphrase fallback modes), plus crafted damaged and edge variants.
Encrypted bodies use real AES-GCM/PBKDF2 with fictional content. Attachment
bytes and metadata are not encrypted by the capsule body encryption.

The old decrypted-export fixtures retain crypto fields due to the old model
bug. They remain readable for compatibility; new exports must clear the fields.
Delivery packets include a marked PDF cover stub and are not whole-vault restore
bundles. The recorded extra-path fixture was originally unexecuted; the new
failure suite now verifies its explicit rejection rather than silent flattening.

The historical matrix had existing reliability expectation failures. It must
not be relabeled as a pass. `tools/archive_compatibility/run_matrix.py` records
new execution evidence separately, including fresh producer/reader combinations.

Never replace these fixtures with a real backup, key, journal or attachment.
