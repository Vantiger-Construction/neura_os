# Developer guide

The default branch is `Neura`. Read [AGENTS.md](../AGENTS.md) and the relevant
workflow before choosing SDKs or running tools.

## Toolchains and dependencies

Exact Flutter and Rust versions are declared in
[coverage CI](../.github/workflows/neura-coverage.yml): use `FLUTTER_VERSION`
and `RUST_VERSION` rather than an older guide or a floating release. Dart ships
with Flutter. Android and Windows also need the native tools in their workflows:
Android SDK/JDK/Gradle and Visual Studio C++/Windows SDK components respectively.

From the source root:

```sh
flutter pub get --enforce-lockfile
cargo fetch --manifest-path rust/Cargo.toml --locked
```

Do not add provider, signing or production-backend secrets just to run unit
tests. Configured packages have a separate path in
[CONFIGURED_BUILDS.md](CONFIGURED_BUILDS.md). Never commit credentials.
Regenerate adapters/bindings only when required, using the paired generator
versions for the branch.

## Develop and validate

Use `flutter run` for a supported development target. On Windows, `Neura.bat`
provides the repository launcher and may build the app and repair its shortcuts.
The Linux agent setup prepares dependencies; it does not prove native Windows
or Android device behavior.

Run checks appropriate to the change:

```sh
dart format --output=none --set-exit-if-changed lib test
dart analyze --fatal-infos
flutter test --no-pub --concurrency 2 --timeout 2m
cargo fmt --manifest-path rust/Cargo.toml --all -- --check
cargo test --manifest-path rust/Cargo.toml --locked --all-targets
cargo clippy --manifest-path rust/Cargo.toml --locked --all-targets -- -D warnings
bash tools/ci/lint_workflows.sh
git diff --check
```

The source-quality workflow uses the committed analyzer policy. Inspect any
SDK-generated policy edits before accepting them. Preserve locks unless the
task deliberately updates dependencies. Run focused regressions during
iteration, then relevant complete CI lanes before claiming validation.

Use current Windows/Android packaging workflows for platform builds. A host
build does not establish physical audio, microphone, startup, storage or
migration acceptance. See [Actions setup](GITHUB_ACTIONS_SETUP.md) and
[contribution guidance](../CONTRIBUTING.md) for review and delivery.
