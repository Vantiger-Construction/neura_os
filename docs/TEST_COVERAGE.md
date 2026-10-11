# Automated test coverage

`Neura test coverage` runs on relevant pull requests into `Neura`, relevant pushes
to `Neura`, and manual dispatch. It measures the existing suites without adding
percentage gates, application dependencies, model downloads, or cloud services.

## Suites and scope

| Report | Collection | Scope |
| --- | --- | --- |
| Flutter (Linux) | `flutter test --no-pub --coverage` | Entire `test/` suite, including encrypted-memory, Safe Mode, consent, voice, and offline tests. |
| Rust (Linux) | `cargo llvm-cov --locked --all-targets --no-report` | All current unit and integration targets, including IPC and real-child session lifecycle tests using the portable process backend. |
| Rust (Windows) | Same instrumented command | Includes the native MSVC process/handle/job lifecycle backend. |

The Flutter SDK remains 3.47.5. The coverage compiler is Rust 1.99.0, matching the
current hosted Rust adapter CI. `llvm-tools-preview` matches that compiler;
`cargo-llvm-cov` 0.9.1 is installed as a verified prebuilt binary by a pinned
install-action commit. Neither package manifest nor lockfile is changed.
Flutter dependency restoration enforces the committed lockfile; Rust uses
`--locked`. No tool is installed on the self-hosted Windows runner.

The HTML/JSON summary counts only measured executable lines in `lib/**/*.dart`
or `rust/src/**/*.rs`. Generated `.g.dart`, `.freezed.dart`, `frb_generated*`
bridge code, external packages, test directories, and `rust/src/ipc_tests.rs`
are excluded from the production summary. The original LCOV is retained so these
choices can be audited. No authored production module is excluded by name.

Flutter may omit libraries that the tests never import. Rust can omit code not
compiled for the current platform. The report lists these **unmeasured files**
separately: their executable-line counts and coverage are unknown. The displayed
percentage is therefore measured-source line coverage, not an assertion that
every application file was exercised. Linux and Windows results stay separate;
they are not averaged. Branch coverage and stable-Rust doctest coverage are not
claimed. Neither result replaces native microphone, installed-app, or device tests.

The native launcher intentionally clears inherited environment variables and
can forcibly terminate its child. Coverage does not relax this allowlist or
forward `LLVM_PROFILE_FILE` to the sidecar. Child-process-only execution may not
flush a profile; direct IPC tests instrument the sidecar code independently.
The launcher/process owner is covered in the test process. This is a coverage
limitation, not permission to change production lifecycle or credential handling.

## Reports

Each job appends its actual line count/percentage, test outcome, and tested commit
to the Actions run summary. For pull requests, the tested SHA is GitHub's merge
commit used by checkout, not a mislabeled branch-head SHA.

Download the `neura-flutter-coverage-*` or platform-specific
`neura-rust-coverage-*` artifact from the workflow run. Reports are retained for
14 days and include:

- `index.html`: per-file line coverage, uncovered line ranges, and unmeasured files;
- `summary.json`: exact counts, uncovered line numbers, test outcome, and tested SHA;
- `summary.md`: the same overview shown in the Actions run summary;
- `raw.lcov.info`: original compiler/Flutter output for LCOV-compatible tooling.

If tests fail and usable LCOV exists, reports explicitly say **PARTIAL**; the
test failure remains a job failure. Missing, malformed, truncated, or empty
production coverage fails reporting rather than manufacturing a passing result.
Artifact uploads run even after failures. A job stopped before collection, a
cancelled run, or a platform outage may have no report; the upload reports missing
files. No percentage threshold is used, including when measured coverage is 0%.

Artifacts contain source paths and coverage counters, not source text, test logs,
credentials, transcripts, vault contents, binaries, or raw process profiles.
They stay in GitHub Actions; there is no Codecov/Coveralls account, upload token,
public publishing, runtime telemetry, or background cloud call.

## Cost, storage, and reproducibility

Coverage is isolated from release workflows on disposable GitHub-hosted runners.
It does not consume the self-hosted Windows runner's 8 GB validation headroom or
Android staging space, add instrumented code to release binaries, or alter any
existing security gate. Each language/platform suite runs once; Rust reporting
reuses its profiles. Test/build concurrency is bounded to two, jobs time out at
45 minutes for Flutter and 30 minutes for Rust, and superseded runs are cancelled.
Rust targets are placed under `runner.temp`, incremental compilation is disabled,
debug info is limited to line tables, and instrumented targets are not cached or
uploaded. This trades hosted Actions minutes for predictable local disk usage.

Hosted Actions billing, runner availability, artifact-storage policy, and action
allowlists can still block collection or delivery independently of Neura code.
Inspect the new coverage job's annotations before changing application code or
loosening any policy. Existing release checks remain independently required.

To validate the reporter locally, run:

```sh
python -m unittest discover -s tools/coverage -p 'test_*.py' -v
```

To reproduce Flutter collection, restore with `flutter pub get --enforce-lockfile`,
then use the workflow's `flutter test` command. For Rust, install the pinned tool
and matching LLVM component, then use the workflow's clean/test/report commands.
Render either LCOV with `python tools/coverage/report.py`; `--help` lists the
required language, label, output, tested commit, and test-outcome arguments.
