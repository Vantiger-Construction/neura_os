# Configured Windows and Android packages

The existing Windows and Android workflows can build against the currently
selected Supabase project. This configures the client only: journal sync still
requires sign-in and opt-in, and it does not authorize AI requests or actions.

## Build settings

In repository Settings > Secrets and variables > Actions > Variables, set:

| Repository variable | Value |
| --- | --- |
| `NEURA_SUPABASE_URL` | The existing project's HTTPS origin |
| `NEURA_SUPABASE_PUBLISHABLE_KEY` | Its public `sb_publishable_...` client key |

Use the same project on both platforms. Do not commit actual values or define
files. Never use a service-role, secret, database or model-provider key here.

Run **Neura Local Runner Check** and **Neura Android Package** on
the branch containing these workflow changes. For manual dispatch, leave
`require_sync_configuration` checked. A requested configured build fails if the
settings are missing; partial or invalid settings always fail. Ordinary PR
validation keeps its local-only behavior if both settings are absent.

Android packaging for same-repository maintainer PRs runs on a fresh
GitHub-hosted Ubuntu 24.04 VM. It uses the pinned Flutter version, JDK 17,
locked dependencies and the existing public-client configuration helper. It
verifies the APK signature, application ID and version code before publishing
the same download-verified prerelease assets. This avoids using laptop disk
space for PR Android builds. Fork PRs do not receive release-publishing access.

Manual Android dispatch still uses the local Windows runner and its existing
storage safeguards: 16 GB free on the system/build volume, or an eligible
non-system build volume with 12 GB plus separate SDK staging space. The hosted
job only removes unrelated preinstalled toolchains from its disposable VM.

The helper creates a temporary UTF-8 Dart define file and removes it after the
job. The Flutter defines remain `SUPABASE_URL` and `SUPABASE_ANON_KEY`; the latter
accepts the public publishable key. The workflows retain their existing tests,
analysis, toolchain checks and Windows packaged-launch check.

## Outputs and recovery

Configured Windows runs publish the entire release directory as a ZIP, including
its executable, DLLs and data. Android package runs publish the installable debug
APK. Required deliverables use a GitHub prerelease keyed by PR head and packaged
source commit, rather than GitHub Actions artifact storage. Each platform publishes
the binary, a build manifest and SHA-256 checksums as separate release assets.

The delivery step verifies the preserved-package checksums before publication,
then downloads every published asset through GitHub's release API and compares its
byte length and SHA-256 digest with the local file. The job fails unless all three
assets upload and download cleanly. The manifest records the PR head, checked-out
commit (the merge commit for a PR run), project origin, config digest, run identity,
release tag and pending device-QA status. It contains no client key.

Before upload, local jobs retain the deliverable on the selected runner volume:

```text
<build volume>\neura-packages\windows\<run id>-<attempt>
<build volume>\neura-packages\android\<run id>-<attempt>
```

The exact path appears in the preserve step and job summary. These directories
are outside the generated `neura-ci` cleanup tree and are not overwritten. A
required release upload or download-verification failure fails the job even if
compilation succeeded; the retained copy remains available to the runner's
operator. Do not classify a delivery failure as a Flutter compile failure.

Hosted Android packages are staged under the ephemeral runner's temporary
directory. The download-verified GitHub prerelease is their durable copy; a
failed hosted delivery requires rerunning the job because the VM is discarded.

Prerelease assets do not use the Actions artifact quota or the old three-day
artifact expiry. Remove superseded CI prereleases after the replacement head is
verified. Runner recovery copies also require manual cleanup after delivery and
verification; they are not deleted automatically.

## Release gates

A successful configured build is not device acceptance. Verify sign-in and
Windows–Android sync, offline recovery, stale-update conflicts, Safe Mode with
microphone off and no cloud access, local-only voice, fresh approval for each
cloud request and action, and private-context restrictions on real test devices.
Local journals remain authoritative. Record device and build identity with the
results before release. Full Flutter CI and the deployed migration history
remain independent release gates.

