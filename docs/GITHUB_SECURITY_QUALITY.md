# GitHub security and quality setup

## Repository settings

Configured on November 3, 2026 UTC for `Vantiger-Construction/neura_os`:

| Feature | Configuration |
| --- | --- |
| Private vulnerability reporting | Enabled; `SECURITY.md` links to the private reporting form |
| Secret Protection | Enabled, including push protection |
| Dependency graph and Dependabot alerts | Enabled |
| Malware alerts | Enabled |
| Dependabot security updates | Enabled, with grouped security updates |
| CodeQL security analysis | Existing advanced workflow with six language lanes and completeness checks |
| Managed Code Quality | C#, JavaScript/TypeScript and newly enabled Python scans on pushes, PRs and a weekly schedule |
| Paid AI quality scans | Remain off |

Settings are separate from repository files. Verify current state under
[Advanced Security](https://github.com/Vantiger-Construction/neura_os/settings/security_analysis)
and [Code quality](https://github.com/Vantiger-Construction/neura_os/settings/code-quality).
The earlier dated state in `SECURITY_VALIDATION.md` is historical evidence.

## Scheduled dependency proposals

Once `.github/dependabot.yml` reaches the default branch, Dependabot checks
GitHub Actions, Pub, Cargo, the npm sync-test tool, and Android Gradle weekly
on Mondays. Each ecosystem permits at most two open version-update PRs, with
minor/patch updates grouped and major updates reviewed separately. This limit
does not disable security updates. No update is automatically merged.

For Pub, Cargo and npm, `increase-if-necessary` retains a manifest constraint
when it already admits the updated version. Review SDK requirements, coupled
Flutter/Rust bridge versions, native compatibility patches, and lockfile changes
before merging any proposal. Keep Actions pinned to full commit SHAs.

## Source quality checks

`neura-source-quality.yml` adds a hosted Linux check for every PR into `Neura`,
push to `Neura`, and manual dispatch. It reads the exact Flutter version from
`neura-coverage.yml`, restores the committed lockfile, verifies formatting across
`lib` and `test`, and runs `dart analyze --fatal-infos` across the repository.
Flutter's project migration can add analyzer excludes during dependency restore;
the workflow restores the committed policy before analysis so those generated
excludes cannot silently narrow the check.

The check uses read-only repository permissions, SHA-pinned Actions, and no
persistent checkout credentials. It complements managed Code Quality, which
does not provide Dart source analysis, and the existing OSV lockfile audit.
Existing Flutter/Rust coverage, platform builds, privacy tests, and physical
acceptance remain separate requirements.

## Validation and enforcement

Local baseline: default commit `ca7965386fc57d0acbc709f170e33a5587e58b9f`.
The proposed configuration passes checksum-pinned actionlint 1.7.12. Flutter
3.47.5 / Dart 3.13.4 restores the lockfile unchanged, formats 693 application/test
files with zero changes, and reports no strict analyzer issues. The exact
published commit and hosted results are recorded in the setup PR. The managed
Code Quality [setup run](https://github.com/Vantiger-Construction/neura_os/actions/runs/41583585604)
passed Python, C#, JavaScript/TypeScript and result upload on that baseline.

Scans create checks and findings; they do not by themselves prevent a merge.
At setup time the default branch reports `protected: false`, and the existing
`neura safety` ruleset targets no branches. This change does not silently impose
new merge, signature, or review requirements or claim that they are enforced.
The existing CodeQL failure threshold remains High-or-higher for security alerts
and errors for standard alerts. The OSV audit continues to include all known
findings and development dependencies without suppressions.

GitHub still displays an account billing warning. No billing settings, purchased
features, alert access lists, or application privacy controls are changed here.
