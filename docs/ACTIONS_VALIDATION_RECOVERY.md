# GitHub Actions validation recovery

Inspected October 17, 2026 UTC (October 16 in America/Chicago). This is an
additive, temporary Windows validation path for two frozen PR heads. It does
not change either development branch, replace Linux results, remove security
checks, change branch rules, or authorize a merge or public release.

## Account-owner action

The repository belongs to **Vantiger-Construction**, an organization. Its
**Settings → Billing and licensing → Budgets and alerts → Actions** budget
currently shows **$0**, **Usage blocked**, and the checked setting **Stop usage
when budget limit is reached**. Opening that budget also shows **Payment method
is missing** and says a valid payment method is needed before adjusting it.

- Organization budget: <https://github.com/organizations/Vantiger-Construction/settings/billing/budgets>
- The signed-in personal account also displays a failed-payment banner, linking
  to <https://github.com/settings/billing/payment_information>.

An owner/billing manager must resolve the appropriate payment/account restriction
and decide whether to permit a finite Actions budget. No payment details, budgets,
stop-usage controls, or account settings were changed during this investigation.
Do not remove the budget ceiling as an automatic workaround. The observed page
does not establish an outstanding invoice amount or the exact failed charge.
If the owner resolves payment and budget access but the lock remains, contact
GitHub billing support with the affected run URLs; do not keep retrying jobs.

## Current source and existing evidence

| PR | Exact branch head | Passing self-hosted checks | Hosted checks blocked before assignment |
| --- | --- | --- | --- |
| [133](https://github.com/Vantiger-Construction/neura_os/pull/133) | `b822c48be5a871d5a5e8e88825205d70534216d0` | [Windows](https://github.com/Vantiger-Construction/neura_os/actions/runs/38606991242), [Android](https://github.com/Vantiger-Construction/neura_os/actions/runs/38606991385), [State Matrix](https://github.com/Vantiger-Construction/neura_os/actions/runs/38606991261), Living Intelligence and Self-Hosted Check | [Wipe, attempt 2](https://github.com/Vantiger-Construction/neura_os/actions/runs/38606990921), [consent, attempt 2](https://github.com/Vantiger-Construction/neura_os/actions/runs/38606991108), [Flutter/Windows Rust/Linux Rust coverage, attempt 2](https://github.com/Vantiger-Construction/neura_os/actions/runs/38606991038), [both CodeQL languages](https://github.com/Vantiger-Construction/neura_os/actions/runs/38606983738) |
| [136](https://github.com/Vantiger-Construction/neura_os/pull/136) | `c79aca63e861b2e4f9f049f408d27f5103170e58` | [Windows](https://github.com/Vantiger-Construction/neura_os/actions/runs/38897532464), [Android](https://github.com/Vantiger-Construction/neura_os/actions/runs/38897532417), [State Matrix](https://github.com/Vantiger-Construction/neura_os/actions/runs/38897532911) | [Ollama Flutter and both Rust platforms](https://github.com/Vantiger-Construction/neura_os/actions/runs/38897532489), [Flutter/Windows Rust/Linux Rust coverage](https://github.com/Vantiger-Construction/neura_os/actions/runs/38897532439), [four offline-adapter jobs](https://github.com/Vantiger-Construction/neura_os/actions/runs/38897532694), [both CodeQL languages](https://github.com/Vantiger-Construction/neura_os/actions/runs/38897529284) |

All 19 failed hosted jobs in those current-head runs have `runner_id=0`, an empty
runner name, and `steps=[]`. The PR136 preview job was skipped because its
upstream jobs could not start. These results contain no compiler/test execution.
The fresh PR136 Ollama page explicitly reports failed account payments or an
insufficient spending limit. Its Ubuntu image-migration notices are informational.
The older PR136 run 38865660353 is superseded and must not be rerun as evidence
for the current head.

Existing passing PR-triggered checks may check out GitHub's synthetic merge
commit. For example, the PR136 Windows job checked out
`d4be91211f94beef158be37976986cc2b4d06ec5`, merging the current branch head into
`a4e8c5e793d4aa3764c66a47819c395b555c786b`. Its complete Flutter tests, Rust IPC
tests, Windows package build, payload/launch verification, and required asset
delivery all passed. This is current-PR integration evidence; it is not mislabeled
as a direct branch-head checkout or as the missing dedicated coverage result.

The repository runner page shows one available runner, **STEVOLAPTOPYO-neura**,
with labels `[self-hosted, Windows, X64, neura]`, idle at inspection. No Linux
self-hosted runner is listed. The most recent Windows log reported 27.14 GiB
free on C: after checkout; the new run checks current free space independently.

## Supplemental workflow

`.github/workflows/neura-validation-recovery.yml` runs on this repair PR and
manual dispatch. It serializes the two target heads on the existing Windows
runner, with these safeguards:

- Same-repository execution only; read-only PR permission and job-scoped contents
  write permission for private draft report assets; no supplied secrets,
  persisted checkout credentials, application release upload, status
  spoofing, `pull_request_target`, model installation, live benchmark, or cloud
  inference.
- The GitHub PR API must confirm the exact frozen head before checkout. The
  checkout SHA is verified locally and compared with the current PR head again
  when writing the final receipt. A stale/mismatched head fails the job.
- At least 16 GiB free is required on the selected volume. Flutter dependencies
  reuse the existing cache; Rust targets/temp data are isolated under the current
  run. The existing bounded cleanup helper removes generated output after
  artifacts are saved. It preserves source, retained SDKs and shared caches.
- Flutter 3.47.5 uses the existing checksum-verified provisioning helper. Rust
  1.99.0 is selected only for this job, without changing the laptop's default.
  The existing pinned, verified cargo-llvm-cov 0.9.1 installer is retained.
- Reporting uses an installed Python 3.12 or 3.14 executable, checking native
  exit status and runtime version. Python 3.14.4 at `C:\Python314\python.exe`
  passed the coverage-reporter and synthetic benchmark-statistics suites.
  No Python installation or execution-policy change is performed.
- Both heads run the full Flutter suite once with coverage, complete Rust
  `--locked --all-targets` tests, strict Clippy, and all-target Windows Rust
  coverage. Report generation preserves partial/failing outcomes. No test
  failure is converted to success and no test assets are omitted.
- Both heads run consent/turn-safety formatting, strict analysis, focused tests,
  merge-marker detection, and the existing storage-recovery tests.
- PR133 additionally runs the unchanged focused wipe commands with coverage,
  fixture tests, related privacy/encrypted-memory contracts, strict privacy
  analysis and canonical formatting. Only synthetic confined fixtures are used.
- PR136 additionally runs the unchanged focused Ollama and offline-adapter
  Flutter checks, Rust formatting, synthetic benchmark-statistics tests, Windows
  policy checks, and native-owner compilation against genuine Flutter headers.

Coverage is labeled **Windows supplement** and records the tested branch head,
not the repair PR's workflow commit. `validation-receipt.json` separately records
the tested tree, workflow commit, run/attempt, runner, suite outcomes, latest PR
head, and SHA-256 hashes of the source workflow definitions. Coverage artifacts
remain private and expire after 14 days. Logs remain in GitHub Actions.
If Actions artifact storage is unavailable, the existing repository release-asset
delivery mechanism is used for a separate **draft**, report-only prerelease.
Only ten explicitly named receipt/coverage files are eligible (16 MiB per file,
32 MiB total); linked entries are rejected. LCOV is reduced to normalized
repository source paths and numeric line records; external records and function
text are omitted. Source text, test logs, environment dumps, vault files,
packages, and credentials are not included. A SHA-256/size manifest records
included and missing files, target head, workflow commit and run/attempt.
Every uploaded file must pass download-and-hash verification. The draft URL and
manifest digest appear in the job summary. Draft assets do not inherit the
14-day Actions retention period; they are retained for review without automatic
deletion. No existing release or artifact is overwritten or removed.

The artifact upload's failure can be tolerated only after the fallback is
verified. An explicit final delivery gate fails if both routes fail; earlier
validation failures remain failures. Original coverage, receipt and fallback
manifest remain in the run-specific workspace through bounded cleanup even
if remote delivery fails. This is evidence storage, not package publication,
deployment, or authorization to release the application.

The recovery checks are attached to the repair PR. Their receipts provide
evidence about the target commits; they do not manufacture green check statuses
on PR133/136 or satisfy Linux/security requirements by renaming Windows results.
If a target head advances, review the changes and update the frozen SHA and
command-parity comparison before a new run. Do not rerun the stale manifest.

## Remaining gates and smallest continuation

1. Let each supplemental Windows job execute once. Classify preflight/tool,
   download or artifact failures as infrastructure problems. Classify compiler,
   analyzer or test failures only from actual executed-step output.
2. Keep the successful Windows/Android delivery and State Matrix runs. Rebuild
   those packages only if source changes, a result becomes stale relative to the
   tested target/base, or package-specific evidence is invalidated.
3. After the owner restores hosted access, refresh each PR head once. On an
   unchanged head, rerun failed jobs only in the current run IDs listed above.
   Restore the original Linux Flutter/wipe/consent and Linux Rust/coverage lanes;
   Windows supplemental coverage does not prove Linux process semantics.
4. PR136's original hosted preview remains required unless a reviewer explicitly
   establishes equivalence with the already passed Windows package receipts.
   Rerunning its failed upstream jobs should allow the dependent preview to run;
   verify the dependency result rather than repeatedly dispatching everything.
5. Preserve dynamic CodeQL for C# and JavaScript/TypeScript. The earlier PR133
   investigation records GitHub rejecting a dynamic-workflow retry. If that
   limitation persists, use GitHub's supported Code Quality reanalysis controls
   after access is restored; do not disable/recreate the security gate simply
   to obtain a green status.

Neither PR is fully validated while required hosted/security results are missing.
No PR merge or public release is part of this workflow.

## Repair validation before dispatch

The new YAML passes actionlint 1.7.12 with the observed custom `neura` runner
label configured. All Bash blocks and GitHub-script JavaScript parse. Seventeen
critical test/analysis/format/coverage command blocks match the existing workflow
commands byte for byte. Four admission cases reject moved, closed and foreign
PR targets; three receipt cases preserve failed/skipped outcomes and reject a
moved head or mismatched checkout. All 11 existing coverage-reporter unit tests
pass locally. These checks validate the recovery configuration, not the Neura
application suites; Windows execution must provide that evidence.

## October 17 retained-runtime and evidence-storage repair

Run `39004030829` failed at setup-python's unsigned `setup.ps1`. Run
`39010508400` then failed because discovery required Python 3.12 although
the runner has Python 3.14.4 at `C:\Python314\python.exe`. The Python launcher
also lists user-local 3.14 installations; no 3.12 retained-tool-cache entry was
found. Artifact upload separately reported storage quota exhaustion. These
failures occurred before application tests and do not indicate failing suites.

The coverage and benchmark-statistics scripts are standard-library-only; their
annotations require modern Python but no 3.12-specific feature. Both frozen
targets have identical coverage reporter/test blobs. Installed Python 3.14.4
passed all 11 coverage-reporter tests and all 5 synthetic benchmark-statistics
tests. No benchmark, microphone, model or cloud inference was invoked.

`python tools/test_validation_recovery.py` tests the actual workflow blocks:
native nonzero exit despite plausible JSON, unsupported version, missing
runtime, accepted native probe, installed runtime, partial/complete report
delivery, missing/mismatched receipts, oversize and linked entries, a public
repository rejection, API/download checksum failure, and all delivery-gate
outcomes. API calls are mocked and all fixtures are disposable. Run this on
Windows with Node and the retained Python; no policy override is needed.
The workflow YAML also parses and the application validation command blocks
remain unchanged. Exact-head recovery execution is still required; local
infrastructure tests do not substitute for either target's application suites.

## October 17 retained Bash discovery repair

Run `39047686488` selected Python 3.14.4 successfully, then PR #133 failed
before application tests with `bash: command not found`. Git was on PATH via
`C:\Program Files\Git\cmd`, but its Bash directory was absent. The private draft
report fallback delivered and verified the partial receipt and manifest.

The recovery workflow now discovers Bash beside the retained Git executable,
probes it with the runner's `--noprofile --norc -e -o pipefail` options, and
checks bundled utilities before adding `bin` and `usr\bin` to job-local
`GITHUB_PATH`. It rejects missing or nonzero probes, including a result
that prints the expected marker and exits 7. The regression test reproduces
missing Bash on a Git-cmd-only PATH and verifies the resulting runner shell.
No installation, machine PATH change or execution-policy override is added.
Existing Bash command blocks and both frozen target SHAs remain unchanged.

The initial discovery step in run `39050871600` was rejected before execution
because the runner-generated PowerShell script was unsigned. Discovery now uses
the existing `actions/github-script@v8` Node runtime, with direct bounded native
process calls and `core.addPath`; it does not generate a PowerShell script or
change signing policy. Tests invoke the actual v8 action entry point with the
runner's Node 24, checking real Git Bash and job PATH output, then injected
missing executable, nonzero exit, missing marker, timeout and discovery failures.
All other workflow steps remain unchanged.

For local tests, set `NEURA_GITHUB_SCRIPT_ENTRY` to an available v8
`dist/index.js` when the runner action cache has been cleaned. The official v8
entry point tested from temporary storage had SHA256
`4af8211e8a7ef1f8e03e03fab7fdbd204c1108713af5c18b3d48f04d194c9abe`.
The harness supplies offline action inputs and makes no GitHub API calls.
