# November 2026 dependency refresh

Neura 1.5.1+2 refreshes the stable app dependency graph and its build tooling.
This supersedes the version inventory in the September/October
[Flutter compatibility audit](FLUTTER_3_47_COMPATIBILITY.md). The native build,
device, encrypted-state, and release-package validation gates still apply.

## Toolchains and dependency decisions

| Component | Selected version |
| --- | --- |
| Flutter / bundled Dart | 3.47.9 / 3.13.7 |
| Rust | 1.99.1, pinned in `rust-toolchain.toml` and CI |
| Android Gradle Plugin / Gradle | 9.5.0 / 9.8.2 |
| Kotlin / Java | 2.4.21 / 17 |
| Android command-line tools | 23.0, verified Windows archive |
| Android compile SDK / NDK | 37.0 / 28.2.13676358 |
| Flutter/Rust bridge, runtime and generated bindings | 2.13.0 |
| Supabase Flutter | 2.18.3, exact pin |
| Secure storage | 10.3.1, exact migration-stage pin |
| PGlite SQL migration tests | 0.5.14 |
| Apple deployment minimums | iOS 15 / macOS 12 |

Flutter's minimum version determines the runtime Dart floor. The app retains
its Dart 3.0 language version, avoiding a repository-wide formatting rewrite.
Flutter and Gradle downloads retain verified SHA-256 pins. Actions are pinned
to the commits resolved from their stable release tags on November 2, 2026.
Android keeps built-in Kotlin enabled and the legacy AGP DSL required by the
Flutter plugin. The app's target SDK continues to follow Flutter's default.

`flutter pub upgrade` changed 126 packages. All remaining `pub outdated`
entries have a documented constraint:

- **Secure storage 11** removes the legacy cipher readers used by v9 installs.
  Ship v10 first and exercise its migration on existing installations. A later
  v11 release must also account for users skipping intermediate app versions.
  All Neura credential and encryption-key stores now explicitly use
  `resetOnError: false`, `migrateOnAlgorithmChange: true`, and
  `migrateWithBackup: true`. Storage failures must not silently reset keys.
- **cross_file 0.3.5+5** is the latest version allowed by current file-picker,
  image-picker, and sharing plugins. Their constraints exclude 0.4.0.
- **screen_retriever 0.2.2** is required by window_manager_plus 1.0.5, whose
  published constraint excludes 0.3.x.
- `flutter_secure_storage_darwin` follows the staged storage migration;
  `built_collection`, `qr`, `material_color_utilities`, and `test_api` remain
  constrained by their parent packages or Flutter SDK. No dependency override
  forces an unsupported combination.
- `hive_generator` was unused (no Hive adapter annotations or generated adapter
  registration). It was removed to unblock the current analyzer and Freezed.
  Hive's stable runtime and existing stored data format remain unchanged.
- The Unity prototype's embedded packages remain tied to its separate pinned
  Unity editor; this app refresh does not replace that editor or its reference
  assemblies.

The Rust graph upgrades Tokio, Reqwest, Axum, Tungstenite, getrandom, and other
registry dependencies. WebSocket text conversions and configuration builders
were migrated without changing session limits. The RustCrypto adapters remain
necessary for FRB and Axum's older hash constraints; the resolved graph still
uses patched `block-buffer` 0.12.1. See [the adapter audit](../rust/compat/README.md).

## App compatibility changes

### Avatar workflow compatibility

The inherited motion and conversation jobs must also use Flutter 3.47.9;
Flutter 3.47.5 cannot restore this branch's locked dependencies. Their checkout
and artifact actions use the same reviewed pins as the other refreshed jobs.

Conversation validation composes the current SAPI pin and motion's merged commit
`4e66869078442392e2dde0282826c7a97c9dee74` in a disposable checkout. Motion #149's
deleted feature branch is no longer required: the pinned merged commit must be
an ancestor of the reviewed base. It creates diagnostics before any guard or merge, and preserves
the failing phase, expected/observed heads and unresolved paths on failure.
Only successful composition records a combined tree. The fixture tests run with
the workflow's Git Bash on Windows, and the shell script retains LF endings.

The SAPI branch carries an older version of the conversation workflow itself.
A checkout-local merge driver retains this PR's version of that one workflow
file and records its source head in the report. Application, test, dependency
lock and other conflicts still fail normally; native-viseme assertions and
strict artifact uploads remain required. Fixtures cover both the workflow-only
resolution and rejection of application conflicts. This CI repair does not merge
the SAPI feature into the dependency PR or alter application/dependency files.

### Runtime migration

File picking uses the new single-file API and byte streams. Chat retains its
32 KB cap. Encrypted backups retain their 25 MB cap even when a provider cannot
report file size. Export passes encrypted bytes to the picker, allowing Android
content URIs rather than assuming every selected destination is a local path.
Legacy attachment and vault imports also read the selected file through the
new API. Sharing uses `SharePlus.instance.share(ShareParams(...))`, and device
authentication uses local_auth's explicit `biometricOnly` parameter.

The selected Android scripts were inspected from the resolved pub archives:

| Plugin | AGP 9 decision |
| --- | --- |
| android_file_picker 2.1.2 | Upstream detects built-in Kotlin; remove old file_picker override. |
| home_widget 0.10.0 | Native build still selected external KGP under the legacy DSL. Re-audit and retain the guarded override; align compile SDK 37 and Kotlin with the app. |
| record_android 2.2.0 | Upstream uses built-in Kotlin; remove old override. |
| share_plus 13.3.1 | Upstream detects built-in Kotlin; remove old override. |
| speech_to_text 7.5.0 | Upstream uses built-in Kotlin; remove old override. |
| flutter_tts 4.2.5 | Retain exact-version/upstream-hash guard and local Kotlin migration. |

Windows `local_auth_windows` 2.0.2 still requires the reviewed C++20/COM
correction. Its source guard and receipt were refreshed after comparing the
published plugin source; its new authentication result and availability cases
remain intact. Media and notification source guards still match their resolved
packages. See [security validation](SECURITY_VALIDATION.md).

## Reproduce generated bindings

With the pinned Flutter and Rust toolchains on PATH:

```sh
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
flutter_rust_bridge_codegen generate --rust-input crate::api --rust-root rust --dart-output lib/rust_bridge --no-web --no-auto-upgrade-dependency --no-build-runner --no-dart-fix
dart run build_runner build
dart format lib/rust_bridge
```

## Validation

- Full Flutter suite: 1,021 tests passed, including the content-URI and byte-limit
  regressions; 38 focused migration/backup/voice tests also passed.
- Flutter analysis: no issues.
- Rust: 113 tests passed; Clippy with `-D warnings` passed; formatting passed.
- PGlite migration/revision/ownership checks passed; seven relay tests passed.
- Ten security-helper tests passed. Actionlint passed with the repository's
  actual `neura` runner label configured (shellcheck not run).
- OSV Scanner 2.7.0: zero known advisory matches across 225 Pub, 244 Cargo, and
  one npm package, using all findings and no suppression rules.
- Android arm64 debug APK: Gradle `assembleDebug` passed with AGP 9.5.0,
  Gradle 9.8.2, Kotlin 2.4.21, compile SDK 37.0 and a full JDK 17.
- Windows locked-source CMake corrections pass against the resolved packages;
  changed upstream source is rejected and authentication-result handling is
  preserved. Native compilation and CodeQL run in GitHub CI.
- Apple builds and on-device migration checks require platform validation.

A dependency upgrade is not an installed-app rollout. Before release, exercise
upgrades from a v9 secure-storage installation on Android and Windows, preserve
existing encrypted records and credentials, and verify explicit wipe behavior.

## Explicit Rust TLS provider and extraction repair

Security [run 41419872039](https://github.com/Vantiger-Construction/neura_os/actions/runs/41419872039),
job `125192996721`, built the Windows application
successfully but failed the unchanged incomplete-extraction gate. Its verified
SARIF/native diagnostic artifacts show six compiler-error metrics from two
`aws-lc-sys 0.47.0` translation units: `stdalign_check.c` (alignment probe) and
`crypto/thread_win.c` (MSVC linker pragma). These were introduced transitively by
Reqwest 0.13's default Rustls provider; they were not Dart compilation failures.

Retained failure artifacts (archive SHA-256 verified before inspection):

- C++ SARIF, artifact `13130023923`: `5a212e3b47968fda9d00c33ab13c07ef8d46c59aa5616ca2839254b9755a1e65`.
- Native extraction diagnostics, artifact `13130264226`: `169054cb0a6cf0802f1159bc93dad61884704805e8a9ef99044d71d45ede520b`.

Keep Reqwest 0.13.5 and Rustls 0.23.46, explicitly selecting the maintained Ring
backend already used by the pre-refresh application. `rustls-no-provider` requires
installation before any Reqwest client is built, even a loopback HTTP client.
All app, sidecar, evidence and test clients use `http_client::builder`, which
initializes the provider once without starting a request. Callers retain their
existing consent, loopback-only, proxy, redirect, timeout and cancellation rules.
Rustls still verifies certificates and hostnames with the platform trust roots.

The lockfile removes AWS-LC and unused supporting packages; no remaining package
version changes and no registry crypto implementation is patched. This retains
Ring's TLS cipher/key-exchange capabilities; AWS-LC-only features, including its
post-quantum groups and FIPS provider, are not enabled. Revisit that choice only
with working extraction and platform validation. Neither provider choice makes
Neura a FIPS-validated application.

`rust/tests/http_tls.rs` performs real loopback TLS handshakes with public test
fixtures: a locally trusted certificate succeeds, an untrusted CA fails, and a
trusted certificate with the wrong hostname fails. The test CA is never installed
globally. The existing complete Rust suite also exercises client construction,
local boundaries, cancellation and native session teardown.

The CodeQL workflow, compiler-error gate, query set, build tracing and artifact
retention remain unchanged. Current-head Windows extraction must pass before this
repair is accepted; local Linux TLS tests alone cannot establish that result.

Local validation of this repair with Rust 1.99.1: all 116 Rust tests, warning-free
Clippy across all targets, Rust formatting, and all 10 security-helper tests pass.
OSV 2.7.0 scanned 454 locked packages (225 Pub, 228 Cargo, 1 npm) with zero known
advisory matches and no suppressions. Locked Windows MSVC dependency resolution
selects Ring and includes no AWS-LC packages; this is not a Windows build result.

Provider API: [Reqwest 0.13 TLS configuration](https://docs.rs/reqwest/latest/reqwest/tls/).

## Primary release references

- [Flutter changelog](https://github.com/flutter/flutter/blob/3.47.9/CHANGELOG.md)
- [Flutter Windows release index](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json)
- [Rust 1.99.1](https://blog.rust-lang.org/2026/10/15/Rust-1.99.1/)
- [AGP 9.5 compatibility](https://developer.android.com/build/releases/agp-9-5-0-release-notes)
- [Secure storage migration notes](https://pub.dev/packages/flutter_secure_storage/changelog)
- [Supabase Flutter changelog](https://pub.dev/packages/supabase_flutter/changelog)
- [File picker API](https://pub.dev/documentation/file_picker/13.3.1/file_picker/FilePicker-class.html)
