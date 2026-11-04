# Neura GitHub agents

Six manually selected GitHub Copilot custom agents live in `.github/agents/`.
They share `AGENTS.md` and `.github/copilot-instructions.md`. These are coding
assistants for the repository, separate from Neura's in-app companion and its
runtime cloud-consent controls.

## Choose an agent

| Agent | Use it for | Example task |
| --- | --- | --- |
| Neura CI Repair | Failing checks, source composition and toolchain mismatches | Diagnose the current failing jobs on PR #162; fix confirmed causes and report new-head results. |
| Neura Privacy and Memory | Consent, encrypted storage, journal preservation and wipe | Review the current wipe flow for unregistered key owners and late writes; fix a reproduced defect. |
| Neura Voice and Avatar | Local speech, startup listening, visemes and motion | Check Stop/background behavior across native speech and avatar callbacks; add a focused regression. |
| Neura Offline Intelligence | Rust adapters and bounded local conversation | Improve one offline conversation behavior within the existing memory and consent limits; use synthetic fixtures. |
| Neura Dependencies | Toolchains, package updates and migration compatibility | Check the current dependency PR for SDK mismatches and encrypted-storage migration risks. |
| Neura Release Readiness | Windows/Android packages, launch failures and evidence | Verify the latest candidate's artifact identity and platform evidence; list remaining device acceptance gaps. |

Examples identify tasks to assign; they are not scheduled jobs or current status
claims. Each profile uses explicit file, search, edit, shell and GitHub tool
access. Automatic model selection of these specialists is disabled. Profiles
contain instructions, not a security sandbox: GitHub permissions, firewall,
review requirements and runtime consent still enforce their own boundaries.

## Start a task

1. Open [GitHub agents](https://github.com/copilot/agents) and select
   `Vantiger-Construction/neura_os` with the `Neura` branch.
2. Select the appropriate Neura custom agent from the agent picker. Refresh the
   page after a profile change if it has not appeared yet.
3. Provide one concrete issue/PR URL, the desired outcome and acceptance checks.
   Ask for a focused PR and exact-source validation evidence.
4. Inspect its changes and current-head checks before merging or releasing.

GitHub also supports choosing a custom agent when assigning an issue to Copilot.
Repository profiles must be committed to the default branch to become available
there. Their presence does not purchase a Copilot plan, enable an organization
policy or start a session. If the picker is unavailable, inspect the signed-in
account's Copilot entitlement, organization/repository agent policy and any
billing restriction. Do not bypass those controls or add paid services silently.

## Prepared development environment

`.github/workflows/copilot-setup-steps.yml` contains the required
`copilot-setup-steps` job on an ephemeral GitHub-hosted Ubuntu runner. It reads
exact Flutter/Rust version pins from the checked-out branch's coverage workflow,
installs the matching tools, restores locked Pub/Cargo dependencies and records
the source and versions. It neither runs the application tests nor installs
models or configures production credentials. Native Windows/Android validation
remains in the existing platform lanes.

Use **Actions → Neura agent environment → Run workflow** to check setup. Changes
to the setup or coverage workflow on `Neura` also trigger that check. Existing
**Neura Actions validation** checks workflow syntax. No scheduled agent runs,
automatic issue assignments, release publishing or auto-merge are installed.

GitHub uses this setup for sessions running on GitHub Actions; other environments
may require their own setup. A failing step can leave an agent with an incomplete
environment, so agents must inspect the setup result before claiming tests ran.
Keep the coverage workflow's exact quoted stable-version keys when upgrading;
update the extractor if that workflow's structure changes.

## Existing Claude workflow

`.github/workflows/claude.yml` already handles trusted `@claude` mentions. It is
separate from these Copilot profiles and requires its existing
`ANTHROPIC_API_KEY` Actions secret. This setup does not create/read that secret,
change its permissions, or establish that Claude's provider account is usable.

## References

- [Creating GitHub custom agents](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/create-custom-agents)
- [Agent profile configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
- [Agent development environment](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/customize-the-agent-environment)
- [Neura Actions setup](GITHUB_ACTIONS_SETUP.md)
