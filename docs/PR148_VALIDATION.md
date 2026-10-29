# PR #148 repair and validation

Date: October 29, 2026. Original head:
`03cb048920df7207ebd65c39b753032fc517c8cd`.
Target/base: `Neura`, `29ffea432b2fe09dea9012858b4d3e9f7214ccfe`.

## Review findings

All eight findings were confirmed. An isolated checkout of the original head,
with only a clock/service injection seam and synthetic fixtures added, fails
nine regression cases: the eight findings plus the separate learning-read
consent defect. No real microphone, model, account or user data is involved.

| Finding | Correction | Regression evidence |
| --- | --- | --- |
| Slow preference write blocks banners | Record the open in memory; queue persistence without awaiting it in evaluation | `proactive_banner_review_regression_test.dart`: stalled routine write |
| Delayed write crosses full-data wipe | Preserve the original queue; defer preference deletion and report an incomplete wipe if draining times out; refuse resume while writes remain | `data_wipe_routine_lifecycle_test.dart`: timeout, failed resume, retry, fresh post-wipe history |
| Welcome-back Open has no destination | Omit Open for presence cards and reject an accidental presence navigation action | `proactive_banner_card_test.dart`: no Open/Review and only a dismissed outcome |
| Disabled learning/proactivity leaves stale history usable | Gate reads and writes, observe policy changes, forget the baseline and queue deletion; re-enable starts fresh | Service regressions: disabled learning, saved refusal, both off/on transitions |
| Quiet hours/cooldown consumes welcome | Persist one pending arrival, acknowledge only after the rendered frame | Service regressions: quiet hours, cooldown, private room, unshown retry and shown consumption |
| Concurrent evaluations duplicate cards | One evaluation owner and receipt-owned candidate reservations | Service regression: simultaneous calls with paused platform writes |
| Timezone changes distort local-hour classification | Persist name and UTC offset; reset on mismatch, including DST; discard untagged v1 data | `initiative_clock_regression_test.dart`, routine-model JSON tests |
| Clock rollback triggers a false late-night card | Reject all initiative scans before the last-seen instant | Clock regression: rollback into another late-night hour |

Additional tests reject stale pre-wipe receipts, invalidate offered cards on
consent revocation or Safe Mode, remove revoked greetings from the widget,
and check JSON timestamp bounds and UTC/local same-hour deduplication.
Histogram-cap tests use UTC so their subject is storage bounds; DST resets
are tested explicitly using `America/Chicago`.

## Exact dependency findings and repair provenance

Original [security run 40632024689](https://github.com/Vantiger-Construction/neura_os/actions/runs/40632024689),
audit job `122630363416`, artifact `12792081624`. The downloaded ZIP was
verified against SHA-256:
`e03cdb394f0692b824f34aa14dde7011319bac7eaa0a825b550dce6d70394c27`.
Its `osv.json` identifies:

| Package on the original head | Advisory | Applied correction |
| --- | --- | --- |
| `block-buffer 0.10.4` | `GHSA-qwgh-2vcv-g2f7`, panic-corrupted buffer position | `block-buffer 0.12.1` through registry RustCrypto 0.11 implementations |
| `tokio 1.53.1` | `RUSTSEC-2026-0386`, unsafe `AsyncFd` constructor ownership | `tokio 1.53.3` |

The nine dependency repair files are byte-for-byte copies of
[#146](https://github.com/Vantiger-Construction/neura_os/pull/146) head
`5bba1c85a01e8f1331d70d219c31d99fe1c941c5`:

- `rust/Cargo.toml`, `rust/Cargo.lock`;
- the five files in `rust/compat`;
- `rust/tests/digest_compat.rs`;
- `tools/Start-Neura.ps1` (includes `rust/compat` in payload fingerprints).

The two unpublished forwarding adapters retain the existing FRB and WebSocket
consumer APIs while re-exporting unmodified upstream MD5/SHA-1. They contain
no cryptographic algorithm. See `rust/compat/README.md` for limits and removal
criteria. No UI, memory or recovery changes from #146/#147 were imported.
Only the privacy workflow edited for these regressions also adopts #146's
three verified action pins. Other workflow versions remain outside this fix.

No advisory is suppressed. Scanner policy, severity handling, CodeQL extraction
gates, provider policy, loopback restrictions, cloud approvals, encryption and
microphone permissions are unchanged.

## Validation commands

Toolchains: checksum-verified Flutter 3.47.5 / Dart 3.13.4 and Rust 1.99.0.
The Linux Flutter archive SHA-256 is
`2132e990f236f8d22e7c6314b29a191a95b10d7cbcfec9b4e2e303d996652cbb`.
Local Flutter commands use `CI=true FLUTTER_SUPPRESS_ANALYTICS=true`; the
supported CI flag skips Flutter's Azure metadata environment detector.

```sh
flutter pub get --enforce-lockfile
flutter test --no-pub --reporter expanded --concurrency 2 --timeout 2m \
  --coverage --coverage-path=/tmp/pr148-flutter-coverage.lcov
flutter analyze --no-pub --fatal-infos \
  lib/dashboard/proactive_banner_service.dart \
  lib/dashboard/widgets/proactive_banner_card.dart \
  lib/intelligence/routine_model.dart lib/intelligence/initiative_source.dart \
  lib/src/core/data_wipe_service.dart \
  test/dashboard/proactive_banner_review_regression_test.dart \
  test/dashboard/proactive_banner_card_test.dart \
  test/data_wipe_routine_lifecycle_test.dart \
  test/intelligence/routine_model_test.dart \
  test/intelligence/initiative_clock_regression_test.dart \
  test/helpers/data_wipe_fixture.dart
cargo test --manifest-path rust/Cargo.toml --locked --all-targets
cargo clippy --manifest-path rust/Cargo.toml --locked --all-targets -- -D warnings
cargo fmt --manifest-path rust/Cargo.toml --all --check
python -m unittest discover -s tools/security -p 'test_*.py' -v
python tools/security/scan_dependencies.py --scanner /tmp/pr148-osv-scanner \
  --output /tmp/pr148-repaired-audit
git diff --check
```

Flutter: the complete Linux suite passes all **938 tests**, including the
routine, widget, wipe, encrypted-memory, consent, Action Loom, offline-chat
and lifecycle contracts. Strict analysis of all eleven changed Dart files
reports no issues; canonical formatting passes. Rust: 113 tests pass;
strict all-target Clippy and formatting pass. All ten
security-helper tests pass. The checksum-pinned OSV-Scanner 2.7.0 scan reports
zero advisory matches across 227 Pub, 213 Rust and one npm package.
The repaired Rust lockfile SHA-256 is
`fa1339c93190c141558f767c8da5cf8e2c953601cf6933691dfc066420d7bdb3`.

Local test results do not replace current-head hosted security, Windows/native,
integration checks or reviewer acceptance. No physical Windows/Android device
acceptance is claimed. Merge remains conditional on those gates; the fresh
hosted results and merge decision belong in the PR discussion after pushing.
