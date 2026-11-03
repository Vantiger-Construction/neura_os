# GitHub repository setup

## Repository services

Neura uses GitHub-hosted source, pull requests, Actions, security/quality scans,
Discussions and manually selected coding agents. See
[security and quality setup](GITHUB_SECURITY_QUALITY.md),
[Actions setup](GITHUB_ACTIONS_SETUP.md) and [agents](GITHUB_AGENTS.md).

The weekly dependency proposals and strict Flutter source-quality workflow are
active on `Neura` following [PR #164](https://github.com/Vantiger-Construction/neura_os/pull/164).
They do not automatically merge updates or publish releases.

## Default-branch merge policy

Activation is pending: GitHub requested account identity confirmation when saving
the prepared rules. The last verified saved configuration targets no branches,
so the policy below is not yet enforced. Complete GitHub's **Confirm access**
prompt, finish saving, and verify that the live ruleset targets `Neura` before
treating these checks as required.

The `neura safety` ruleset is intended to target the default branch, `Neura`,
with no bypass actors. Its baseline is:

| Rule | Purpose |
| --- | --- |
| Pull request required | Changes are visible as a reviewable PR before integration |
| Review conversations resolved | Open code discussions must be addressed |
| Branch up to date | Required checks cover the current target branch |
| Verified signatures and linear history | Use signed squash merges for an attributable, linear default branch |
| Force pushes and deletion blocked | Preserve default-branch history |
| Required GitHub Actions checks | Workflow configuration, strict Flutter source analysis and locked-dependency auditing |

Exact required check names are `Validate workflow configuration`,
`Flutter formatting and strict analysis`, and `Locked dependency vulnerabilities`.
Workflow validation now runs for every PR into `Neura`, so a docs-only change
does not leave its required status permanently pending. Push validation retains
its existing path filter.

The approval count remains zero rather than requiring a second maintainer who
may not be available. This does not provide independent approval or override
an individual PR's review requirements. CodeQL, platform builds, coverage,
privacy contracts and physical acceptance remain additional evidence to inspect;
passing these three baseline checks does not establish release readiness.

Settings are stored by GitHub separately from these files. Inspect the live
[ruleset](https://github.com/Vantiger-Construction/neura_os/rules/20882440)
for current enforcement. This guide is not itself a protection mechanism.

## Contribution intake

The issue chooser has bug and feature forms plus links to private vulnerability
reporting and Discussions. Blank issues remain available. A PR template requests
behavior, exact-source validation and compatibility information.
[CONTRIBUTING.md](../CONTRIBUTING.md), [SUPPORT.md](../SUPPORT.md) and the
[developer guide](DeveloperGuide.md) provide the entry points.

Keep branches used by source-composition workflows until their consumers have
approved replacement pins. Automatic branch deletion remains off.

## Owner decisions and external prerequisites

- GitHub has displayed an account billing warning. Billing resolution belongs
  to the account owner; this setup does not purchase services.
- The signed-in account lacks Copilot cloud-agent access. Profiles and toolchain
  setup exist, but an eligible license is required to start those sessions.
- No project-wide license is selected by this setup. Existing file/third-party
  notices remain authoritative; redistribution terms require an owner decision.
- Signing credentials, store submissions, production deployment and physical
  Windows/Android acceptance are outside repository administration.

For recent validation, use the setup PR's exact source and run links rather than
assuming a historical green result applies to a changed branch.
