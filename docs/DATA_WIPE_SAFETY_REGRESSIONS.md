# Full-data-wipe regression testing

These tests exercise the actual `NeuraDataWipeService.wipeAllLocalData()`
orchestration. They use newly created synthetic storage, mocked durable
preferences and secure storage, and a synthetic recorder. Never substitute
application directories, user recordings, credentials or a physical recorder.

`test/helpers/data_wipe_fixture.dart` redirects application documents, support,
plugin temporary storage, system temporary storage and environment-based
bootstrap logging to one disposable fixture. Its IO guard rejects paths outside
that fixture. A fake HTTP client rejects requests. Microphone and speech channels
reject calls; the recorder-specific test replaces the recorder platform with an
in-memory fake that writes synthetic bytes only. Durable preferences are modeled
separately from the SDK's in-memory cache. Provider/model tests use isolated
credential owners and fake strings.

## Reproducible commands

Use the repository's Flutter 3.47.5 and committed lockfile:

```sh
flutter pub get --enforce-lockfile
flutter test --no-pub --reporter expanded --concurrency 2 \
  --coverage --coverage-path=coverage/wipe/lcov.info \
  test/data_wipe_service_test.dart \
  test/data_wipe_service_full_test.dart \
  test/data_wipe_service_lifecycle_test.dart \
  test/data_wipe_credentials_test.dart \
  test/data_wipe_microphone_test.dart
flutter test --no-pub --reporter expanded --concurrency 2 \
  test/encrypted_memory test/core/memory_graph_service_test.dart \
  test/neura_provider_credentials_test.dart \
  test/startup/native_speech_safe_mode_test.dart \
  test/living_intelligence \
  test/intelligence/action_loom_fresh_approval_test.dart \
  test/intelligence/fresh_approval_lease_test.dart
```

`.github/workflows/neura-data-wipe-safety.yml` runs these commands, strict analysis
and formatting on hosted Linux. It preserves focused LCOV for 14 days. The
existing `Neura test coverage` workflow independently runs the complete Flutter
suite and both Rust coverage jobs. Check the tested head and test outcome before
using any coverage number; failed runs produce partial evidence.

## Contracts exercised

- Complete deletion of exact app-owned document/support targets and every
  current temporary artifact pattern, including both temporary roots and
  bootstrap logs. Prefix/suffix neighbors, nested unrelated files, neighboring
  secure entries and a directory symlink's target survive.
- Clear returning false, throwing, or claiming success while leaving durable
  preferences cannot report a successful wipe. Retry removes remaining state.
- Filesystem/lookup and secure-store failures are independent, aggregated and
  redacted; failures do not skip later cleanup targets.
- An interrupted key deletion cannot complete the wipe or release Safe Mode.
  Ambient/wake-word gates stay closed, opt-ins are reset, and clearing Safe Mode
  still requires a restart.
- An encrypted graph append paused past the three-second drain deadline makes
  the wipe fail. When released, its generation check purges the late write.
  Retry/repeated cleanup, stale-key decryption, suspended graph writes, logs and
  later credential saves cannot restore deleted private data.
- Full-wipe provider revocation immediately hides the cached key even if secure
  deletion fails. Model initialization/reads are blocked, including a read that
  began before revocation. A restart cannot resurrect a legacy build credential;
  its non-secret migration tombstone intentionally remains.
- Ignored backup passphrase deletion is reported as incomplete.
- A failed stop of one synthetic sleep recorder does not skip another recorder.
  A retry reattempts unverified stops; repeated cleanup never restarts capture.

## Recorded failing evidence before corrections

Base production source: `90146013940f452f7de845598ea8e278a997a385`.

| Run | Reproduced production failure |
| --- | --- |
| [38531377435](https://github.com/Vantiger-Construction/neura_os/actions/runs/38531377435) | Cached provider key/configured models remain usable after failed deletion; an in-flight model read returns its revoked secret. This first run also exposed an overly strict HTTP-client allocation mock, corrected in the fixture. |
| [38531764037](https://github.com/Vantiger-Construction/neura_os/actions/runs/38531764037) | False/ignored durable preference clear and ignored backup passphrase deletion return success. The other 12 focused cases passed, including the late graph writer. |
| [38532132979](https://github.com/Vantiger-Construction/neura_os/actions/runs/38532132979) | One failed recorder stop skips the next recorder. The other 15 focused cases passed. Recorder fixture disposal also needed to await the fake before restoring the platform. |

These are synthetic regression findings, not evidence that an actual user's
deletion failed. They do not establish physical-device/native-driver acceptance,
cloud-session behavior or removal of previously shared external copies. No
physical device or live cloud session is initialized by this suite. The fixes
preserve the restart boundary, Safe Mode microphone-off and no-background-cloud
rules. See the pull request's current validation evidence for corrected-head
results; do not merge automatically.
