# GitHub Actions commit pins — October 24, 2026

## Scope and source identity

Inspected `Neura` commit `29ffea432b2fe09dea9012858b4d3e9f7214ccfe`
(tree `57d4f8fce82c48bc465064683770823858aa2074`). The latest
[default-branch security run](https://github.com/Vantiger-Construction/neura_os/actions/runs/40041885681)
analyzed that revision. Its Actions job
[120714632078](https://github.com/Vantiger-Construction/neura_os/actions/runs/40041885681/job/120714632078)
completed successfully, including the existing extraction-completeness gate.
Its retained [Actions SARIF](https://github.com/Vantiger-Construction/neura_os/actions/runs/40041885681/artifacts/12539188041)
has ZIP SHA-256 `9d9d13a27298f1bf42beabab572a0ac07c88e95fc38fd297a0d1a32ac1cd0758`.
CodeQL 2.27.3 reported **16** `actions/unpinned-tag` results with security
severity **5.0 (medium)**. These are supply-chain risk findings, not evidence
that an action was compromised.

The exact baseline locations are below. Line numbers refer to the inspected
commit, before the additional Rust input lines:

| Workflow under `.github/workflows/` | `dtolnay/rust-toolchain@stable` | `subosito/flutter-action@v2` |
| --- | --- | --- |
| `cut-beta-build.yml` | 25 | 28 |
| `neura-coverage.yml` | — | 63 |
| `neura-1.5.1-consent-turn-safety.yml` | — | 68 |
| `neura-adaptive-intent-validation.yml` | — | 67 |
| `neura-data-wipe-safety.yml` | — | 41 |
| `neura-help-guidance.yml` | — | 31 |
| `neura-offline-text-adapter.yml` | — | 84 |
| `neura-ollama-chat.yml` | 92 | 67, 93 |
| `neura-phase4-package-validation.yml` | 126 | 47, 129, 359 |
| `neura-windows-tts.yml` | — | 35 |

A full inventory found **56** mutable direct references across **19** workflows,
including the 16 reported third-party references and 40 first-party references.
This correction pins all 56. All **67** direct external `uses:` references
across the 21 workflows are then full 40-character commit SHAs. Existing
immutable references, including the entire security workflow, are retained.

## Verified upstream identities

On October 24, each version selector was resolved through the intended upstream
repository's Git refs API and matched against its published, non-prerelease
release tag. Each resulting commit was fetched from that same repository;
GitHub reported a valid verified signature for all six selected commits.
The five release pins match the commits their existing major tags resolved to;
this change introduces no action major-version upgrade.

| Existing reference | Immutable commit | Verified identity |
| --- | --- | --- |
| `actions/checkout@v5` | `fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09` | [v5.1.0](https://github.com/actions/checkout/releases/tag/v5.1.0) |
| `actions/upload-artifact@v6` | `b7c566a772e6b6bfb58ed0dc250532a479d7789f` | [v6.0.0](https://github.com/actions/upload-artifact/releases/tag/v6.0.0) |
| `actions/setup-python@v6` | `ece7cb06caefa5fff74198d8649806c4678c61a1` | [v6.3.0](https://github.com/actions/setup-python/releases/tag/v6.3.0) |
| `actions/setup-java@v5` | `b6effb05e454b25005698d916606bdc6ffcbf961` | [v5.7.0](https://github.com/actions/setup-java/releases/tag/v5.7.0) |
| `subosito/flutter-action@v2` | `1a449444c387b1966244ae4d4f8c696479add0b2` | [v2.23.0](https://github.com/subosito/flutter-action/releases/tag/v2.23.0) |
| `dtolnay/rust-toolchain@stable` | `683b588c487a69d01f6c6ddf40f036ff682cc2c8` | [Upstream master commit](https://github.com/dtolnay/rust-toolchain/commit/683b588c487a69d01f6c6ddf40f036ff682cc2c8), with explicit `toolchain: stable` |

The official ref endpoints are
`https://api.github.com/repos/{owner}/{repo}/git/ref/tags/{tag}`
for both the major selector and release tag, and
`https://api.github.com/repos/dtolnay/rust-toolchain/git/ref/heads/master`.
Commit metadata is available at each upstream repository's
`/commits/{sha}` API endpoint. Future updates must repeat the upstream identity,
release, metadata and compatibility review; comments are labels, not verification.

## Rust selector handling

The upstream [pinning guidance](https://github.com/dtolnay/rust-toolchain/blob/683b588c487a69d01f6c6ddf40f036ff682cc2c8/README.md#choice-of-full-length-commit-sha)
requires full-SHA pins to come from `master` history: generated channel/version
branch commits can eventually be garbage-collected. Therefore the current
`stable` branch head `b725eda525362e7cf34af9a7243cac1e3f01a7ec` was inspected
but deliberately not used as the pin.

The chosen master commit's `action.yml` requires a `toolchain` input.
Its action content matches the inspected stable branch except that input's
required/default declaration. All three callers explicitly pass
`toolchain: stable`. This preserves the existing rolling Rust stable policy
without relying on a channel branch as executable code. It does **not** pin the
downloaded Rust compiler version. Existing explicit Rust 1.99.0 steps and other
SDK/version selectors are unchanged; compiler-policy changes need separate review.

## Compatibility and boundaries

The upstream action metadata and READMEs were inspected at the selected commits.
Checkout v5.1.0, setup-python v6.3.0, setup-java v5.7.0 and upload-artifact v6.0.0
use Node.js 24 and require Actions Runner 2.327.1 or newer. This requirement
already applied to their corresponding mutable tags. Flutter v2.23.0 and the
Rust action are Bash composite actions supporting the workflows' existing
platforms. Flutter's cache support also requires Runner 2.327.1 or newer.
The actual self-hosted runner binary version was not attested during this review;
its existing minimum-version requirement remains an operational prerequisite.

Runner labels, events, PR checkout refs, permissions, credentials behavior,
conditions, artifact paths/retention, timeouts, test/build commands, SDK selections
and all application privacy and consent boundaries are preserved. No branch rule,
alert threshold, required check, suppression, exception or bypass is changed.
`neura-security.yml` remains byte-for-byte identical to the inspected base,
including its fail-closed audit and extraction-completeness checks.

Direct action pinning is not a fully hermetic build. The selected Flutter
composite still invokes upstream `actions/cache@v5` internally; that upstream
reference is outside these authored workflows. Tool downloads and rolling SDK
selectors also retain their existing behavior. No cache is disabled and no
vendored fork is introduced to conceal this remaining boundary.

## Validation and review gates

Local validation of the resulting workflow changes:

- Official actionlint **1.7.12**, archive SHA-256
  `8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8`:
  all 21 workflows pass schema/expression checks. A temporary config declares
  the existing self-hosted `neura` label. ShellCheck and pyflakes are unavailable,
  so optional integrations were disabled explicitly (`-shellcheck= -pyflakes=`).
- All 21 YAML documents parse with duplicate-key rejection. An independent
  comparison of complete parsed workflows allows only the six verified
  reference substitutions and the three explicit stable inputs; every other
  workflow setting and step is identical.
- All 67 direct external references are full SHAs; each of the 56 replacements
  matches the verified mapping. `git diff --check` passes.
- Existing security-helper suite:
  `python3 -m unittest discover -s tools/security -p 'test_*.py' -v`:
  **10 tests pass**, including rejecting incomplete scans and retaining findings.

These checks do not execute the Windows, Android, Flutter or Rust build matrix,
and do not establish that GitHub has resolved existing alerts. Fresh
PR-specific CodeQL Actions results and the normal required CI/reviewer gates
must be inspected for the resulting commit before merging.

The inspected baseline security run's separate locked-dependency job
[120714631767](https://github.com/Vantiger-Construction/neura_os/actions/runs/40041885681/job/120714631767)
failed with **one advisory/package match**. This is independent of action
pinning; the finding and fail-closed behavior remain in scope of their existing
security gate. No dependency remediation or all-green security result is claimed
by this correction.
