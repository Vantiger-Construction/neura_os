# PR #217 follow-up validation

This follow-up implements the five scoped recommendations in the November 16,
2026 compatibility review. Its task PR is
[#224](https://github.com/Vantiger-Construction/neura_os/pull/224).
Do not treat implementation, a successful synthetic test, or an uploaded build
as physical-device acceptance or release approval.

## Source and implementation

The starting default-branch commit was
`384cde1470149ad3b5e2e33c9638e0f0d8859773`, tree
`071c15af742517abc2e9719874b81aa673274771`. It already contains #217 and the
journal regression correction in #223. The five direct Flutter resolutions,
Android signing configuration, encrypted formats and Windows notification C++
source guard remain unchanged. #221/#222 are separate Android-tooling trials;
this follow-up does not adopt their SDK patch or claim their findings resolved.

| Recommendation | Implemented behavior | Evidence required |
| --- | --- | --- |
| P1: Sleep recorder safety | Check foreground, Safe Mode, restart-required recovery, fatal recovery, profile/wipe suspension and disposal before permission and native Start. Revoke pending starts synchronously. Serialize Stop, retain failed/timed-out shutdown for retry, and retain live-registry ownership until native disposal completes. | Sleep safety, disposal/wipe and existing microphone-wipe tests; then real microphone indicator/release observations. |
| P2: Active record consumers | Ambient and voice-pack capture end on stream close/error, platform Stop or route pause. Clear application timers/subscriptions/state; suppress late callbacks and automatic resume; block reuse after unconfirmed Stop. | Controlled record-platform regressions, including delayed permission, native Start, Stop failure and disposal. These fixtures never open a microphone. |
| P3: Notifications | Unsupported platforms have disabled controls with a Windows-only explanation. Service entry points enforce saved opt-in and invalidate first-use delivery across Safe Mode/recovery. Cancellation can initialize its backend without permitting delivery. | Platform-fake/UI tests; then Windows first-use DLL and actual scheduled-reminder cancellation observations. Android notification delivery remains unsupported. |
| P4: Native evidence | Reuse hosted Windows security compilation and Android startup builds. Retain commit/tree/lock hashes, a complete verified Windows Release ZIP with every payload hash, and verified Android application/version/signer identity. | Current-head hosted jobs and downloaded-archive inspection. Keep source identity and diagnostics separate. No release publication or expanded runner/write permissions. |
| P5: Targeted regressions | Extend existing picker tests for current dialog failures and empty files; smoke-test the real Weekly Snapshot and Recap screens with zero, one and multiple synthetic samples and mouse/touch input. | Current-head focused and complete Flutter suites. OS file-provider/dialog behavior and visual clipping on devices remain separate. |

An earlier #217 green build used a different tree from its integrated squash
commit. Use the selected candidate's own commit/tree and receipts. A green result
on an earlier revision cannot clear a changed candidate. GitHub's PR test-merge
SHA can differ from the branch SHA; compare source **trees** and retain both.

## Automated validation record

The initial #224 head was `86b5c3cc699508d587d37640a722063c1aef957a`, tree
`d295999d34993136a800985cbd4bb08d7d59f57a`.
Its [Android focused run](https://github.com/Vantiger-Construction/neura_os/actions/runs/44064718938)
passed 77 tests and failed one new UI test's platform-override cleanup. This was
a fixture failure, not device evidence; native Android compilation was skipped.
The cleanup was corrected without removing an assertion. The first
[source-quality run](https://github.com/Vantiger-Construction/neura_os/actions/runs/44064718853)
failed canonical formatting; its retained correction patch was applied.
Subsequent candidate results must be recorded at their own exact revision.

Local dependency-free checks passed: release identity/archive/upgrade tests,
security-helper regressions, avatar source-composition regressions, actionlint,
and whitespace checking. Local Flutter setup was blocked by automatic approval
review when it attempted an instance-metadata request. No local Flutter result
is claimed; use the hosted pinned Flutter 3.47.9 jobs.

## Inspect the candidate packages without installing

1. Download the **same candidate tree's** `neura-windows-candidate-RUN-ATTEMPT`
   artifact and `startup-voice-android-RUN-ATTEMPT` artifact. Retain the GitHub
   run URLs, branch/head, checkout/tree and archive digests.
2. Windows: the outer artifact contains `neura-windows-release.zip`,
   `PACKAGE_MANIFEST.json` and `SHA256SUMS.txt`. Check the inner ZIP SHA-256
   against `SHA256SUMS.txt` before extraction. The ZIP includes the manifest
   and the complete native Release bundle. Compare manifest source/lock hashes
   with the chosen candidate. After extraction, compare **every** manifest
   file's byte length and SHA-256; check the executable, engine DLL, `data/app.so`
   and Flutter assets. Never deliver an EXE by itself.
3. The receipt checks the EXE and engine DLL's x64 PE headers, archive inventory,
   ZIP CRCs and every archived payload hash. This establishes static bundle
   identity. It does not establish a publisher signature, clean device launch,
   Windows privacy permission, microphone release or offline-model performance.
4. Android: inspect `android-startup-voice-package/PACKAGE_MANIFEST.json` and
   verify its APK SHA-256. The existing SDK `apksigner verify --print-certs`
   and `aapt dump badging` establish application ID, version code and signer.
   The build remains debug-signed test output. An ephemeral hosted debug signer
   is not a persistent production or installed-device signer.
5. Before an Android upgrade, obtain the previous APK for the installed app
   without uninstalling, clearing storage or replacing a key. Run:

   ```sh
   python tools/release/check_android_update.py --build-tools PATH_TO_BUILD_TOOLS PREVIOUS.apk CANDIDATE.apk
   ```

   Exit 0 confirms only the checker's static same-signer/increasing-version
   criteria. Exit 1 blocks the proposed upgrade; exit 2 means incomplete
   verification. A different signer or equal/lower version is a blocker.
   Do not uninstall as a workaround for real-data compatibility.

## Non-destructive physical acceptance

All rows in `evidence/PR217_DEVICE_RESULTS.csv` start **UNVERIFIED**. Record exact
package/source identity before each run. Append dated observations; preserve
failed or superseded evidence. Keep user audio, real journals, keys, prompts,
credentials and health information out of repository artifacts.

### Windows first: target laptop with 8 GB RAM or less

- Use an isolated test account/data location and synthetic journal/vault/consent
  records. Keep the existing app and encrypted memories untouched.
- Measure a ten-minute offline conversation: response latency, peak RAM,
  follow-ups, interruptions, recognition failure, clean Stop and restart
  continuity. Use the explicitly selected local model; retain memory admission,
  no automatic downloads/substitution and fresh cloud approval.
- Before enabling voice, deny microphone access in Windows privacy settings.
  Confirm capture-start failure does not show a live session. A successful
  record plugin permission query alone is insufficient on Windows.
- Exercise Stop immediately after Start, route disconnect, spontaneous capture
  failure, app background/focus return, Safe Mode, recovery and disposal.
  Observe native microphone release. Returning focus, reconnecting an input or
  clearing Safe Mode must not silently start recording.
- Notifications: launch opted out; explicitly enable and test the first native
  use; check unavailable/missing-DLL failure without false success. Schedule a
  synthetic reminder, then verify opt-out, Safe Mode/recovery and restart cancel
  pending schedules. Unpackaged Windows cannot reliably retract delivered
  toasts; distinguish delivered toasts from future scheduled notifications.
- Open/cancel a real file dialog and observe failure recovery. Inspect Weekly
  Snapshot/Recap with empty, one-point and several-point data, repeated touch/
  mouse input, narrow windows and clipping.

### Samsung SM-S366V / Android 16

- Verify signer/version preflight before installation. If incompatible, record
  BLOCKED and preserve the existing installation and data.
- Confirm launch, mic permission denial/grant, native recognition, local output,
  route loss, interruptions, background/foreground, Safe Mode, clean Stop and
  restart continuity. Record a crash/blank launch as failure with redacted logs.
- Exercise SAF selection before/after resume, duplicate filenames, empty or
  unknown-length files, provider-copy failure and interrupted reading. Android
  notification settings must remain visibly unavailable.

### Synthetic-data upgrade and retention

Create synthetic data with the previous compatible build. Record journals,
vault entries, permissions/preferences and an encrypted backup. Upgrade without
reset/uninstall; restart and check exact contents and backup decryption. Compare
ciphertext/key identity where no legitimate write should occur, keeping keys
local. Include cancelled restore and interrupted shutdown/restart observations.
Never run destructive wipe/corruption tests against real memories. Automated
storage fixtures do not establish this installed-app upgrade result.

Until these observations exist, physical acceptance, release readiness and an
upgrade preserving the user's installed encrypted data remain **UNVERIFIED**.
