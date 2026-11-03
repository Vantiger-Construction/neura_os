# Contributing to Neura Companion OS

Start with an existing issue or a small, concrete proposal. Use the bug-report
form for reproducible failures and Discussions for non-sensitive questions.
Report suspected vulnerabilities through [SECURITY.md](SECURITY.md).

## Make a focused change

1. Branch from current `Neura` and read [AGENTS.md](AGENTS.md).
2. Inspect relevant code, tests and workflows. Check open PRs for overlapping work.
3. Use the branch's pinned SDKs and lockfiles. Follow the
   [developer guide](docs/DeveloperGuide.md) for setup and validation.
4. Reproduce defects with a meaningful regression where practical, then fix the
   cause. Keep unrelated formatting and dependency changes separate.
5. Open a PR targeting `Neura`. Explain behavior, validation and platform limits.

Preserve fresh cloud approval, Safe Mode microphone-off, cancellation, explicit
memory consent, encrypted data and local journaling. Use synthetic test data;
never put private content or credentials in issues, logs or fixtures.

## Review and integration

Address review discussions and recheck against the current target branch.
Required checks are a baseline: additional privacy, native, integration and
packaging checks depend on the changed code. Do not silence failures or publish
a release merely because a PR can merge.

Use a signed squash merge for the default branch. Retain branches referenced by
active integration workflows until consumers use an approved replacement.
Do not automatically delete those branches after merging.

Record unavailable runners, approvals and account limits. Queued or canceled
checks are not passes. See [GitHub setup](docs/GITHUB_REPOSITORY_SETUP.md) for
merge policy and [coding agents](docs/GITHUB_AGENTS.md) for task specialists.
