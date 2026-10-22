# Vulnerability validation

This path adds dedicated security analysis alongside the existing managed
CodeQL **Code Quality** checks. It does not replace application tests, consent
and privacy regressions, or maintainer review. The October 22 repair updates four locked Rust packages to patched versions.
Runtime policy and consent boundaries remain unchanged.

## What was already operating

Inspected on October 21, 2026, against default `Neura` commit
`08fd9493038ef2aa6274c3a12402d96299b5b1bb`, tree
`fe748d1f68fa6d71b2056faa74104afc7066a135`:

- Managed Code Quality is enabled. Successful PR-specific runs
  [39232230353](https://github.com/Vantiger-Construction/neura_os/actions/runs/39232230353)
  and [39232251239](https://github.com/Vantiger-Construction/neura_os/actions/runs/39232251239)
  analyzed C# and JavaScript/TypeScript. Inspected C# log 117992694270 records
  `analysis-kinds: code-quality`, `disable-default-queries: true` and
  `uses: code-quality`. Those are not vulnerability scans.
- Advanced Security shows dependency graph, Dependabot alerts, security updates
  and grouped security updates enabled. Automatic dependency submission is
  disabled; there is no `.github/dependabot.yml` version-update configuration.
- An existing GitHub preset automatically dismisses low-impact alerts for
  development-scoped dependencies. This new audit does not inherit that rule:
  it includes development dependencies and all reported vulnerabilities.
- Dedicated CodeQL security analysis still shows **Set up** before this change.
  No repository security-audit workflow, OSV configuration, Cargo audit policy
  or Python dependency manifest/lockfile was present. Secret Protection and
  private vulnerability reporting show **Enable**; their setup is outside this PR.
- Security alert check failure threshold is **High or higher**; standard alert
  threshold is **Only errors**. These settings are unchanged. An analysis job
  successfully uploading results is not a statement that no alerts exist.
- The active `neura safety` ruleset (20882440) contains deletion, non-fast-forward,
  linear-history, signature and Copilot review rules. Its returned include and
  exclude ref lists are empty; the branch endpoint reports `protected: false`.
  Do not infer full enforcement or change rules to make this PR pass.
- A billing/payment banner remains visible. Successful previous runs do not
  guarantee future runner capacity or result-upload permissions.

## Added workflow

`.github/workflows/neura-security.yml` runs on PRs into `Neura`, pushes to
`Neura`, manual dispatch and Tuesdays at 10:23 UTC. The schedule only operates
once the workflow is on the default branch. Existing open PRs are not retroactively
scanned by creating this file; they need an event after adoption or a reviewed
integration containing the workflow. Results never transfer between commits.

| Component | New analysis | Limits |
| --- | --- | --- |
| Native C/C++ | CodeQL `security-extended`, Windows runner, build mode `none` | Heuristic dependency/macro resolution; not a fully traced Windows release build or binary scan |
| C# helpers and Unity prototype | CodeQL `security-extended`, build mode `none` | Unity assemblies and generated sources may be unresolved; not a Unity runtime audit |
| JavaScript/TypeScript | CodeQL `security-extended` | Includes repository tooling and authored TypeScript; no claim about remotely imported dependencies |
| Python tools | CodeQL `security-extended` | Source analysis only; no Python dependency lock exists to establish installed-version coverage |
| Rust services | CodeQL `security-extended`, build mode `none`, Rust 1.99.0 | Requires rustup/cargo; rust-analyzer can execute dependency build scripts/procedural macros on a disposable runner. Linux extraction is not all Windows feature/target combinations |
| GitHub Actions | CodeQL `security-extended` | Workflow source analysis, separate from branch-rule enforcement |
| Flutter/Dart packages | OSV-Scanner 2.7.0, explicit `pubspec.lock` | Known-advisory matching; **no Dart CodeQL source analysis** or Flutter-engine binary audit |
| Rust packages | OSV-Scanner 2.7.0, explicit `rust/Cargo.lock` | Includes optional and target-specific locked packages; does not establish enabled-feature reachability |
| npm test tool | OSV-Scanner 2.7.0, explicit `tools/sync_tests/package-lock.json` | Includes its development dependency; not an inventory of runtime Deno URL imports |

Current [CodeQL language documentation](https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/)
supports Rust (editions 2021 and 2024), but does not list Dart.
[Compiled-language build guidance](https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages)
supports `none` for C/C++, C# and Rust. Kotlin requires a build; this minimal path
does not claim Android Kotlin or Apple Swift coverage. Android Gradle/plugin
dependencies, Flutter/Dart SDKs, downloaded ONNX/native libraries, checked-in
DLLs, Unity assemblies, Deno URL imports and release binaries remain separate
inventory/scanning work. Root `package.json` contains legacy TOML rather than a
valid npm manifest; it is not treated as an installed npm dependency inventory.

### Permissions, isolation and results

All actions are pinned to full commit SHAs. CodeQL uses default security queries
plus `security-extended`, with defaults explicitly enabled and a dedicated
`/neura-security/language:...` result category. It never changes the managed
Code Quality settings or query configuration.

Only the CodeQL job requests `security-events: write`, in addition to
`contents: read`. The dependency job has `contents: read` only. No PAT,
repository secret, deployment credential, app launch, microphone, journal,
memory, model inference or cloud-provider session is needed. Checkout does not
persist credentials. PR checks use `pull_request`, never `pull_request_target`,
on disposable GitHub-hosted runners. Existing fork-approval policies still apply.

[Code scanning is available for public repositories](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/configure-code-scanning/configuring-advanced-setup-for-code-scanning).
Private organization repositories require the applicable Code Security feature.
GitHub Actions policy, runner availability and SARIF upload authorization must
still allow the workflow. A denied upload or missing extractor is **incomplete**,
not a security pass. Raw SARIF is preserved when available even if upload fails;
no permissions are broadened automatically to repair failures.

Successful CodeQL upload is also insufficient when extraction is partial. The
workflow rejects missing/unsuccessful SARIF invocations and error-level tool
diagnostics and reported C/C++ compiler-error metrics, while retaining the reports.
Initial execution exposed the malformed legacy root `package.json` in JavaScript
extraction, compiler errors in three Unity-dependent C# files, and missing Windows
SDK/Flutter/C++ headers in the heuristic C/C++ extraction. Those coverage errors
remain visible failures pending reviewed manifest/Unity/native-build infrastructure
repairs; they are not suppressed or treated as vulnerability findings. Unresolved
NuGet access further limits the C# analysis. A traced Windows build with genuine
Flutter headers is needed to improve native coverage. Medium Actions alerts remain
visible under the existing, unchanged High-or-higher repository alert threshold.

OSV reads only the three named committed lockfiles, with no dependency install,
transitive manifest resolution or call analysis. It contacts OSV/its public
package metadata services using public dependency identities. This is CI
networking, not a change to Neura's local-only runtime or fresh cloud approval.
An explicit empty configuration and `--all-vulns` prevent inherited ignore rules
and reachability filtering. The binary's pinned SHA-256 is
`160c6253e2922e9e0a6a9771c5c4c40a4b3c6090b34a3cdd5e80c96cc2e4218b`.

The dependency audit fails on findings (exit 1), scanner/network errors, missing
or empty lockfile extractions, unexpected ecosystems, malformed results and
input mutation (incomplete, exit 2). It preserves full JSON containing every
extracted package/version and advisory, stderr, exact command, binary version/hash,
lockfile SHA-256 values, checkout commit/tree, event SHA, PR head/base and UTC
timestamps. Artifacts are retained for 14 days; keep release evidence before
expiry. CodeQL logs record tool/query versions and extraction diagnostics;
the summary records checkout/tree and PR identities. Review SARIF alerts and
extraction diagnostics as well as job conclusions.

### Reproduce the dependency scan

Download the [official OSV-Scanner 2.7.0 binary](https://github.com/google/osv-scanner/releases/tag/v2.7.0)
for the host platform, verify its published checksum (the workflow pins Linux
x64 above), then run from the repository:

```sh
python3 -m unittest discover -s tools/security -p 'test_*.py' -v
python3 tools/security/scan_dependencies.py --scanner /absolute/path/to/osv-scanner --output /temporary/audit-output
```

No Flutter/Rust SDK or paid scanner account is required for this lockfile audit.
The `no-known-findings` status only describes these inputs and the advisory
service at that timestamp; it is not a vulnerability-free certification.

## Initial dependency evidence — October 21, 2026

Local live OSV-Scanner 2.7.0 (OSV-Scalibr 0.5.3, scanner commit
`bfe2f84abd2f09fe0b83ba7f6dad40d296762f40`) completed at
`2026-10-21T17:17:00Z`, using the default commit/tree above. Workflow and audit
helper files were uncommitted during this local run; the lockfiles were unchanged.
The audited workflow revision and hosted results must be recorded separately.
Seven synthetic evidence/false-green regression tests passed.

| Input | Extracted entries | SHA-256 | Result |
| --- | ---: | --- | --- |
| `pubspec.lock` | 227 (223 hosted, four SDK entries) | `e9181e149802f36055bd4fbd90d924f0c04e19224dca242d002e92258f205a43` | No known advisory matches; SDK entries do not establish SDK vulnerability coverage |
| `rust/Cargo.lock` | 212 (211 registry, one local crate) | `f16536e5619db3544054bb44a5ae02e7632700eb07eef0613cc77c75c45c4ce0` | 11 advisory/package matches across four registry packages; scan correctly exits 1 |
| `tools/sync_tests/package-lock.json` | 1 (`@electric-sql/pglite` 0.5.8) | `ce0e1cb5efdcbc288cb1ce6948ba0b0ee4a6c1ea4e93b22e956900c350cd349d` | No known advisory matches |

| Locked Rust package | Advisory records | Patched version covering these records |
| --- | --- | --- |
| `quinn-proto` 0.11.16 | [0338](https://rustsec.org/advisories/RUSTSEC-2026-0338.html), [0339](https://rustsec.org/advisories/RUSTSEC-2026-0339.html), [0340](https://rustsec.org/advisories/RUSTSEC-2026-0340.html), [0341](https://rustsec.org/advisories/RUSTSEC-2026-0341.html), [0342](https://rustsec.org/advisories/RUSTSEC-2026-0342.html) (all `RUSTSEC-2026-...`) | 0.11.18 |
| `rustls` 0.23.45 | [0346](https://rustsec.org/advisories/RUSTSEC-2026-0346.html), [0347](https://rustsec.org/advisories/RUSTSEC-2026-0347.html), [0348](https://rustsec.org/advisories/RUSTSEC-2026-0348.html), [0349](https://rustsec.org/advisories/RUSTSEC-2026-0349.html) (all `RUSTSEC-2026-...`) | 0.23.46 |
| `rustls-webpki` 0.103.15 | [RUSTSEC-2026-0382](https://rustsec.org/advisories/RUSTSEC-2026-0382.html) | 0.103.16 on the current stable line |
| `webpki-roots` 1.0.9 | [RUSTSEC-2026-0381](https://rustsec.org/advisories/RUSTSEC-2026-0381.html) | 1.0.10 |

These are **high-confidence locked-version matches**, not eleven demonstrated
exploits; related aliases can describe one issue across several packages.
The manifest disables reqwest default features and enables `json`/`rustls-tls`;
it does not explicitly enable HTTP/3. Quinn's enabled-feature inclusion needs
Cargo feature-tree verification. Rustls-specific ECH, Brotli, custom-session
logging and key-exchange conditions also require review. The trust-store and
certificate-verifier advisories deserve priority wherever TLS is active.

Use a separate reviewable update to resolve the four packages to patched versions,
inspect `cargo tree --locked -e features --target ...` for each shipped target,
rerun the audit and existing Rust/Flutter/native/privacy gates, and reconcile the
final release lockfile/binary identity. Do not remove optional dependencies or
add ignores solely to turn the audit green. This scanning PR leaves versions
unchanged and retains the finding failure for review.

## Finding triage

Review the authoritative advisory, locked version, platform, enabled features,
call path and shipped artifact. Deduplicate aliases without deleting affected
package rows. Prioritize remediation; an unproven call path is not evidence of
safety. If a false positive is established, record its rule/advisory ID, source
commit, reasoning, owner and review/expiry date in a reviewed change or alert
discussion. This PR adds no dismissals, severity exclusions, query suppressions,
reachability exemptions or automatic fixes/merges. Keep raw findings available.

## PR failure repairs — October 22, 2026

The root `package.json` was an unused TOML placeholder; it is now a valid private
repository manifest with no npm dependencies. The real Rust manifest remains
`rust/Cargo.toml`; npm test tooling retains its separate lockfile.

Cargo resolved only four patch updates: quinn-proto 0.11.18, rustls 0.23.46,
rustls-webpki 0.103.16 and webpki-roots 1.0.10. A fresh checksum-verified
OSV-Scanner 2.7.0 audit of the modified working tree extracted 227 Dart/SDK,
212 Cargo and one npm entry, and returned zero known advisory matches. The
receipt checkout SHA is the pre-edit parent; its lockfile hashes identify the
modified input. This local result does not replace current-head hosted evidence.
Seven audit-helper regression tests passed.

C/C++ now uses manual CodeQL extraction around a real Windows release compile
with checksum-verified Flutter 3.47.5, Windows SDK and restored locked plugins.
The existing completeness gate remains enforced. A successful hosted run is
required before accepting this infrastructure change; native output is not
published or launched by this security workflow. Other platform configurations
and firmware remain outside this traced Windows build.

C# remains blocked by unresolved genuine Unity editor/test assemblies and
NuGet extraction diagnostics. This repair does not exclude Unity files, create
API stubs, suppress diagnostics or claim complete C# coverage. A compatible
Unity 6000.6.6f1 reference/build environment is still required for acceptance.
Earlier tables and run identities above are historical evidence.

## Native extraction repair — October 22 follow-up

The traced Windows build succeeded, but CodeQL 2.27.3 reported WinRT/coroutine
parse errors with MSVC 19.51 (VS 2026). CodeQL's supported-language matrix
currently lists Microsoft extensions through VS 2022. The security lane now
uses `windows-2022`; compiler diagnostics remain fatal. This is an analysis
toolchain choice, not an application source change or a coverage waiver.

C# now uses a manual compile harness over **every Git-tracked `.cs` file**.
`prepare_csharp.py` downloads the official Unity 6000.6.6f1 Linux archive and
verifies SHA-256 `64ea1568976f4e470a9da4db2576116807798c710523f4d0fe13e27fb8635a44`
(also locally matched Unity's published archive MD5). It extracts genuine
managed assemblies, bundled Test Framework 1.8.0 and Custom NUnit 2.1.0,
compiles the unmodified framework dependency before CodeQL init, and generates
a .NET 8 source-analysis project containing all nine authored C# files.
The prototype's test manifest is aligned to bundled Test Framework 1.8.0.
The authored project is compiled after init without incremental/shared
compilation; the existing completeness gate still rejects compiler errors.
No authored source is omitted, and no API stubs, editor activation, Unity
launch, play-mode test, microphone or native Windows API call is performed.

A local compile of all nine authored files against the genuine references and
unmodified framework succeeded with zero warnings/errors. The .NET 8 harness
is a source-analysis build, not a substitute for Unity editor/player builds,
assembly-definition boundaries or physical-device acceptance. The retained
receipt records every authored source and reference hash. A fresh hosted
CodeQL run must confirm extraction before accepting this repair.

Authoritative sources: [CodeQL supported compilers](https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/),
[Unity release](https://unity.com/releases/editor/whats-new/6000.6.6f1),
[Unity release metadata](https://services.api.unity.com/unity/editor/release/v1/releases?version=6000.6.6f1).
