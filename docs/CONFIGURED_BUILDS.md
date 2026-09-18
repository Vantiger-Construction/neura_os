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

Run **Neura Local Runner Check** and **Neura Self-Hosted Android Package** on
the branch containing these workflow changes. For manual dispatch, leave
`require_sync_configuration` checked. A requested configured build fails if the
settings are missing; partial or invalid settings always fail. Ordinary PR
validation keeps its local-only behavior if both settings are absent.

The helper creates a temporary UTF-8 Dart define file and removes it after the
job. The Flutter defines remain `SUPABASE_URL` and `SUPABASE_ANON_KEY`; the latter
accepts the public publishable key. The workflows retain their existing tests,
analysis, toolchain checks and Windows packaged-launch check.

## Outputs and recovery

Configured Windows runs upload the entire release directory as a ZIP, including
its executable, DLLs and data. Android runs upload the installable debug APK.
Each package includes a build manifest and SHA-256 checksums. The manifest records
the checked-out commit (the merge commit for a PR run), project origin, config
digest, run identity and pending device-QA status. It contains no client key.

Before upload, both jobs retain the deliverable on the selected runner volume:

```text
<build volume>\neura-packages\windows\<run id>-<attempt>
<build volume>\neura-packages\android\<run id>-<attempt>
```

The exact path appears in the preserve step and job summary. These directories
are outside the generated `neura-ci` cleanup tree and are not overwritten. A
configured package upload failure fails the job even if compilation succeeded;
the retained copy remains available to the runner's operator. Retrieve that copy
from the runner if GitHub artifact storage is exhausted. Do not classify an
upload quota failure as a Flutter compile failure.

GitHub artifacts expire after three days. Runner recovery copies require manual
cleanup after delivery and verification; they are not deleted automatically.

## Release gates

A successful configured build is not device acceptance. Verify sign-in and
Windows–Android sync, offline recovery, stale-update conflicts, Safe Mode with
microphone off and no cloud access, local-only voice, fresh approval for each
cloud request and action, and private-context restrictions on real test devices.
Local journals remain authoritative. Record device and build identity with the
results before release. Full Flutter CI and the deployed migration history
remain independent release gates.
