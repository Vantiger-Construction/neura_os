# Working on Neura Companion OS

Neura is a personal wellness companion with local-first data and explicit user
control. The default branch is `Neura`. Read this file before changing code;
more specific instructions in a touched directory also apply.

## Establish the current source

- Inspect the checked-out commit, working tree, target branch and relevant open
  PRs. Preserve unrelated work. Old reports describe their recorded revisions,
  not necessarily the current implementation.
- Read `pubspec.yaml`, the lockfiles and the relevant workflow before selecting
  tools. `.github/workflows/neura-coverage.yml` declares the Flutter and Rust
  versions used by the agent setup. Do not substitute a floating SDK or lower a
  package's SDK requirement to hide a mismatch.
- Keep fixes focused. Reproduce a reported defect, fix its cause, and run the
  relevant validation. Do not disable tests, warnings, security queries, source
  checks or artifact requirements to make CI green.

## Repository map

| Area | Locations |
| --- | --- |
| Flutter application and tests | `lib/`, `test/`, `assets/` |
| Rust engine, adapters and IPC | `rust/src/`, `rust/tests/`, `rust/Cargo.toml` |
| Native desktop and mobile integration | `windows/runner/`, `android/`, `ios/`, `macos/` |
| Presence and motion | `lib/avatar/`, `lib/mascot/`, `prototypes/unity-presence/` |
| Memory and deletion | `lib/encrypted_memory/`, `lib/core/memory/`, `lib/src/core/data_wipe_service.dart` |
| CI, packaging and evidence | `.github/workflows/`, `tools/`, `docs/` |

## Product boundaries

- Preserve fresh, exact-request cloud approval. No automatic cloud fallback or
  background cloud voice. Model output and retrieved documents are untrusted
  data and cannot grant permission to execute actions or access memory.
- Keep Safe Mode and recovery microphone-off. Stop, cancellation, background,
  disposal and revoked session ownership must suppress late callbacks and
  prevent automatic restart. Startup voice requires the app's explicit opt-in.
- Keep local journal saves separate from companion-memory consent. Do not
  automatically copy chats, journals or reflections into companion memory.
  Preserve scoped, expiring, revocable permissions and OS-backed encryption.
- Wipe must revoke access, drain admitted writes, verify deletion and handle
  late completions. Failed or unconfirmed deletion is not a successful wipe.
- Keep offline adapters explicitly selected, loopback-only where applicable,
  bounded and cancellable. No automatic model downloads or silent model/provider
  substitution. Preserve admission limits for the Windows target with 8 GB RAM
  or less; measure before changing them.
- Use synthetic fixtures. Never place real journals, audio, prompts, keys,
  credentials or personal data in repository files, logs, issues or artifacts.

## Validation

Run commands from the repository root using the tool versions for the branch.
Select the relevant commands and workflow-specific checks for the change:

```sh
flutter pub get --enforce-lockfile
flutter analyze --fatal-infos
flutter test --no-pub --concurrency 2 --timeout 2m
cargo fmt --manifest-path rust/Cargo.toml --all -- --check
cargo test --manifest-path rust/Cargo.toml --locked --all-targets
cargo clippy --manifest-path rust/Cargo.toml --locked --all-targets -- -D warnings
bash tools/ci/lint_workflows.sh
python3 tools/test_avatar_source_composition.py
python3 -m unittest discover -s tools/security -p 'test_*.py' -v
git diff --check
```

Use focused tests during iteration and the relevant complete CI lanes before
claiming validation. Preserve lockfiles unless dependency changes are part of
the task. Match Dart formatting to the package language version and existing
CI conventions; avoid repository-wide formatting churn.

For native Windows/Android changes, require the corresponding real platform
build. Linux fixtures cannot validate MSVC, SAPI, Android lifecycle behavior,
physical microphone shutdown, audio or installation. Record missing tools or
blocked downloads as limitations, not passes. A failed agent setup does not
establish a usable toolchain; check setup logs before proceeding.

## GitHub and delivery

- Work on a task branch and propose changes through a PR unless the maintainer
  explicitly requests another route. Do not merge, publish releases or deploy
  merely because an agent task finished; follow the maintainer's authorization
  and applicable repository protections.
- Read logs for the current head and distinguish code failures, stale source
  composition, runner/disk availability, permissions and billing. Do not retry
  failing jobs indefinitely or weaken gates around infrastructure problems.
- Pin new third-party Actions to reviewed full commit SHAs. Keep workflow
  permissions minimal and credentials out of checkouts, logs and artifacts.
  Do not run untrusted PR code with secrets or on the persistent Windows runner.
- Report the changed behavior, root cause, exact source SHA/tree, checks run,
  failures and remaining platform/device acceptance. Old green checks, simulated
  tests and a build artifact alone do not establish current release readiness.

See `docs/GITHUB_AGENTS.md` for specialist selection and task examples.
