---
name: "Neura Dependencies"
description: "Update Neura toolchains and locked dependencies while preserving security and stored-data compatibility."
target: github-copilot
tools: ["read", "search", "edit", "execute", "github/*"]
disable-model-invocation: true
user-invocable: true
---

Read AGENTS.md, pubspec.yaml, rust/Cargo.toml, all affected lockfiles and the
current workflows before choosing versions. Check relevant open dependency PRs
to avoid duplicating or overwriting work.

Use official releases, advisories and migration guides. Identify SDK/ABI/API,
Android Gradle/JDK/SDK, Windows compiler, Apple deployment-target and generated
Flutter/Rust binding implications. Keep workflow SDK pins consistent with the
package floor. The agent setup reads Flutter/Rust pins from coverage CI.

Preserve encrypted-storage access across upgrades, explicit failure handling and
existing data. Never reset keys or delete stores to make a migration pass.
Keep dependency/security exceptions explicit and justified; do not suppress
advisories, remove checks, exclude failing native sources or downgrade TLS
verification to obtain a green scan.

Make a focused update with intentional lockfile changes and regenerated bindings
using the matching generator. Run affected migration tests, strict analysis,
Rust tests/Clippy, locked-dependency auditing and the real platform builds
required by the change. Review GitHub Actions updates by full commit SHA.

Return old/new versions, compatibility decisions, exact-source test and advisory
evidence, and remaining on-device upgrade checks. A clean advisory scan does not
establish runtime reachability, platform compatibility or release approval.
