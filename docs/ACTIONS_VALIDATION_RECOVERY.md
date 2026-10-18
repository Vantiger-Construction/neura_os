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

## Junction-relative measured coverage

Run `39051893827`, PR #133 job `117451995160`, passed the complete Flutter
coverage test command but reporting rejected its junction-relative source paths.
The original 303,948-byte LCOV has 411 source records and 28,952 line records;
SHA256 is `0ac263a8de5b404e66627df4ddb99818a6f7438f3280fea52a92418b4173be7d`.
Artifact `12108512687` preserves that run's evidence. Artifact delivery succeeded;
no private draft fallback was used for this attempt.

Recovery now resolves source paths against the logical checkout, verifies their
real paths remain inside the physical checkout, and writes a separate
`normalized.lcov.info`. Untrusted sources receive explicit excluded paths.
All non-source records, including every hit count, remain unchanged. The original
LCOV remains untouched; `path-provenance.json` records both SHA256 values, the
tested head and recovery workflow commit. The frozen target's unchanged reporter
consumes the derivative and retains its empty, malformed and generated-source
gates. The fallback sanitizer applies the same physical containment requirement
and fails explicitly if no measured lines survive; it also preserves provenance.

Read-only replay against the preserved evidence reproduced the original error.
The derivative retained all 411 source and 28,952 line records; the existing
reporter's production filters accepted 409 files and 28,821 measured lines,
including 11,547 covered lines. This is replay evidence, not a new CI result.
Four recovery test methods and all 11 original reporter tests cover Windows and
Unix paths, the actual five-parent junction form, physical escapes, sibling
prefixes, missing/invalid measurements and valid zero-hit lines. Application
sources, test commands and frozen targets remain unchanged.

## Retained PowerShell for the coverage installer

Run `39055161130`, PR #133 job `117461533299`, passed all 816 Flutter tests,
coverage rendering, all 67 Rust tests and strict Clippy. The pinned installer
then failed before executing because its Windows composite step requires
`shell: pwsh`, which was absent from the runner PATH. Rust coverage was skipped.

Microsoft Store PowerShell 7.6.7 is already installed. Recovery probes the
standard PowerShell 7 path and the current user's WindowsApps execution alias
through the existing Node action. It requires PowerShell Core major version 7,
a valid Microsoft signature and an existing physical executable, then adds only
that executable's directory to job-local PATH. Alias discovery uses a native
probe because Node file-existence checks do not recognize this Store alias.
No installation or execution-policy override is added.

The regression harness invokes the actual Node action and the exact pinned
installer's Windows wrapper with a harmless local `main.sh` stub. It checks
environment-injection cleanup, successful exit, propagation of exit 7, and
rejection of unsigned, old, missing and failed runtime probes. The real action
revision `ab6895351a88b908e96a4697860d4ffea5e57dbe`, cargo-llvm-cov 0.9.1,
checksum defaults, all validation stages and frozen targets remain unchanged.

The next attempt exposed a service-context difference: job `117478470882`
runs as `NT AUTHORITY\NETWORK SERVICE`, whose WindowsApps alias is absent.
The interactive-user probe did not establish service availability. The existing
package `C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.7.0_x64__8wekyb3d8bbwe`
and its `pwsh.exe` and `pwsh.dll` explicitly grant NetworkService read/execute.
Discovery now probes that observed physical executable directly, without
enumerating protected WindowsApps directories or using a user-profile alias.
It fails closed if the package is removed or replaced; a future package path
must be reviewed rather than guessed. The standard machine-wide PowerShell 7
candidate remains available.

The signed-runtime preflight now runs immediately after checkout, before SDK
setup and costly application suites. Local tests use NetworkService profile
environment values but do not impersonate the service; only the new CI run can
confirm launch in the actual service context. No identity, ACL, privilege,
execution-policy or installed-software changes were made.

## Rust logical-checkout coverage mapping

Run `39067306418`, PR #133 job `117497523531`, passed the service runtime
preflight, pinned installer and all 67 instrumented Rust tests. Rust reporting
then rejected absolute logical-junction paths after resolving its root to the
physical workspace. Artifact `12116063452` preserves the 221,702-byte Rust LCOV,
SHA256 `c0d2fe558b610d12ea45f1c03d13b9f85302421ab925dae41974e41b93bc18fe`.
It contains 28 source records and 4,206 `DA:` line records, including external
registry and generated/test mappings.

Rust export and rendering are now separated by the same physically confined
normalization used for Flutter. The two normalization bodies are identical and
regression-tested for equality, selecting only the language and report folder.
Raw evidence and every non-`SF:` record remain unchanged; a separate derivative
and hash provenance are written. The original reporter keeps its generated,
test-helper, external-source and zero-measurement gates. Rust provenance is also
included in the private fallback, whose existing containment mapping is tested
with logical absolute paths and `rust/tests/../src` aliases.

Read-only replay reproduced the original error, then accepted 14 production
files, 2,314 measured lines and 1,738 covered lines (75.11%). It normalized 18
in-checkout production-source records before the unchanged reporter's filters
and alias merging. The original hash and all non-source records were verified
unchanged. This replay does not replace fresh CI evidence. Frozen targets,
coverage-tool version, test commands and coverage thresholds remain unchanged.

## Retained CMake preflight for PR #136

Run `39075168199` completed PR #133 successfully. PR #136 job `117536628255`
passed its Flutter/Rust suites, coverage rendering, Clippy, benchmark tests and
native policy checks, then failed before native configuration because `cmake`
was absent from PATH. Artifact `12120475829` preserves that attempt's reports;
the receipt correctly records the overall failure.

The installed Visual Studio 18 Build Tools includes CMake 4.2.3-msvc3 and its
Visual Studio 18 2026 generator. A PR #136-only preflight now locates the C++
installation using retained `vswhere`, checks native exit codes and CMake's
minimum version, verifies the pinned Flutter method-channel header, and
configures the unchanged native gate before expensive test suites. Only after
successful configuration does it add CMake's directory to job-local PATH.
This checks compiler/SDK selection under the actual runner identity without
using an interactive alias or changing machine PATH. The original later native
configuration and Release compilation remain unchanged, including C++20 and
`/W4 /WX`.

The offline harness copies the three frozen PR #136 native-check source files
into a temporary directory, invokes the actual Node action, and compiles the
object target against genuine retained Flutter headers. It also rejects failed
or empty discovery, old/invalid CMake versions and configuration failures before
writing job PATH. Local profile-environment simulation is not impersonation;
actual NetworkService execution remains a fresh-CI check. No installation,
identity, ACL, privilege, policy, billing or artifact changes are involved.

## Interrupted runner and bounded CMake diagnostics

Run `39084931367` PR #133 job `117549381048` reports that the self-hosted
runner lost communication; its job-log endpoint returns 404. Windows records
an unclean reboot before the runner resumed on October 18. That supports a
runner interruption, not an inferred application-test failure.

PR #136 job `117555609783` reached CMake configuration and timed out at
03:33:32 UTC. Earlier retained-tool output also says `timeout reading rustc
version`. Cleanup removed the configure cache/logs. After reconnection, only
the runner listener was present (no worker, CMake, compiler or Rust processes),
with about 8.4 GiB available RAM and 23.5 GB free disk. These later observations
do not establish resource availability at the time of failure or its cause.

The preflight keeps its 60-second timeout and 4 MiB capture bound. Failure
diagnostics now include error code, exit status, signal and the last 4,000
characters of both stdout and stderr, rather than discarding captured output
when a spawn error exists. Known workspace/profile paths and credential-like
values are redacted. The regression verifies this using a synthetic timeout
with captured compiler/SDK messages and a synthetic secret, plus the existing
real retained-tool configure/build check. No timeout, gate or tool selection
was relaxed. Fresh exact-head CI is still needed to distinguish a transient
runner issue from a reproducible configuration problem.

Authorization diagnostics are redacted as complete header values before generic
token masking, including Bearer, Basic, mixed-case, proxy, quoted and folded
forms. Synthetic regressions verify no credential suffix survives while ordinary
diagnostic text remains visible. No actual credential exposure was observed.
