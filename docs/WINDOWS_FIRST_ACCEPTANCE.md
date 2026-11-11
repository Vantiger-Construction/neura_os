# Windows-first stabilization and device acceptance

## Release goal and fixed source

The first release target is ordinary conversation, a practical daily plan, and
local journaling with separately approved companion memory. Use one identified
candidate for this entire cycle. Keep Flutter, Rust, Ollama, model identity,
memory admission and data formats unchanged while reproducing a failure.

Application baseline: `bd109787b6654f3a4371d6c7413f826fb3717be8` on `Neura`.
It includes local hands-free chat (#179), explicit offline readiness (#188),
the clinic-contact hold (#189), and paused new profile activation (#190).
The acceptance tooling changes no application or dependency files. The pending
vault repair (#191) remains independent; this baseline is not approved for
upgrading an installation containing valuable data.

CI identifies the tooling/candidate head and tree in `CANDIDATE.json` inside the
`neura-conversation-acceptance-<full-head>` artifact. The Windows and Android
package jobs run for this change and have their own receipts. Record each
platform's **head, actual packaged source commit/tree, archive SHA-256, and
executable SHA-256**. A PR head, tested merge, and final merged commit may differ.
If either source or bytes change, start a new record; do not combine results.
Do not use the diagnostic kit's historical #161/#177 catalog as evidence of
this candidate. That catalog remains for earlier startup investigations.

## Windows trial, in order

1. Use a separate Windows test account with synthetic data only. A new folder
   alone does not isolate Neura's app data. Keep the ordinary application mode;
   do not enable separate personality profiles. Do not copy, migrate, wipe,
   downgrade, or replace an existing valuable vault or its OS credential store.
2. Download the Windows binary, build manifest and checksum assets from the
   successful package run for this candidate. Verify the manifest identity and
   archive hash against GitHub's recorded asset digest before extraction. Keep
   the full payload together. Record the packaged executable's hash as well.
3. Launch manually. Keep startup speech opt-out for the first trial. Confirm
   the normal dashboard opens and the Stop control is visible. Choose
   **Offline Ollama**, then **Chat options → Offline readiness and controls →
   Check offline readiness**. This explicit check is metadata-only and does not
   prove inference. Fix any reported prerequisite before proceeding.
4. First send a synthetic text request: “Help me plan three manageable tasks.”
   Confirm a useful local answer. Select **Companion**, enable local spoken
   replies, choose **After reply**, and manually start **Talk freely
   (hands-free)**. Keep the app in the foreground. Preserve fresh cloud
   approval and no automatic cloud fallback or model download.
5. Hold a conversation for at least **600 seconds and 10 completed turns**.
   Include follow-up questions and one change to the proposed daily plan.
   Use an external stopwatch to record submit/speech-end to complete-visible
   reply and first audible reply for each turn. Do not switch to the collector
   console to time turns: focus loss intentionally cancels hands-free mode.
   Do not record voices, transcripts or private chat. Manual timings include
   reaction error; no performance target is claimed before measurement.
6. In separate synthetic checks, exercise interruption, Stop, recognition
   failure with explicit retry, a missing/stopped local model, backgrounding,
   Safe Mode and restart. No stale speech/text or automatic listening restart
   may occur. Do not stop an Ollama process in use by another application.
7. Edit one daily plan; save and reopen a synthetic journal entry. Confirm the
   journal is saved locally and is not automatically copied into companion
   memory. Test remembering/reviewing only explicitly approved synthetic notes.
8. Record the **first observed failure**, with its fixed reason code. Stop the
   affected test safely, retain evidence locally, and repair that cause in one
   focused PR with a regression. Repeat against the new identified build.

## RAM sampling and evidence

Run this from a separate 64-bit Windows PowerShell console after manually
launching the verified Neura executable. Get its process ID from Task Manager.
Replace the sample values with the verified package executable's identity.
Create a new evidence directory and never overwrite earlier observations.

```powershell
New-Item -ItemType Directory -Path .\evidence
.\Measure-WindowsConversation.ps1 -NeuraProcessId 1234 -ExpectedExeSha256 '<64 lowercase hex characters>' -OutputFile .\evidence\memory.csv
```

The collector samples for 660 seconds by default; bring Neura forward after
starting it. It reads the selected executable's hash, process working sets and
physical/available RAM. It never starts a model, opens audio, changes permission,
reads command lines or app data, records speech, or uploads anything. Process
exit/reuse or inaccessible measurements end collection without accepting a pass.
Matching Ollama process names may omit unknown runners; sampled working sets
exclude GPU memory and peaks between samples. Inspect paging/responsiveness on
the device as well. This does not replace Neura's Rust memory admission check.

With Python 3.10+ available, create a record and later assess it. Supply **the
same five verified identity arguments** to both commands:

```text
python conversation_trial.py new --platform windows --alias synthetic-laptop --head-commit HEAD --source-commit SOURCE --source-tree TREE --package-sha256 ARCHIVE_HASH --executable-sha256 EXE_HASH --output evidence/trial.json
python conversation_trial.py assess --input evidence/trial.json --memory-csv evidence/memory.csv --head-commit HEAD --source-commit SOURCE --source-tree TREE --package-sha256 ARCHIVE_HASH --executable-sha256 EXE_HASH --output evidence/assessment.json
```

Replace the capitalized placeholders with full lowercase hashes, not branch
names. Fill only observed fixed statuses, UTC timestamps and numeric timings;
keep unexplored cases NOT RUN. No freeform transcript/error fields are accepted.
Failed partial trials can be recorded without completing the rest of the run.
Successful declarations need 10 minutes, 10 matched turn measurements, every
required scenario, explicit isolation/identity/operator confirmation, and a
Windows memory capture covering at least 90% of the conversation.

The strongest output is **OPERATOR_RECORDED_PASS**. It remains an operator
declaration, not independently verified hardware evidence or release approval.
Synthetic helper tests and a prepared template never grant device acceptance.
Keep local reports private; share only inspected, necessary redacted evidence.

## Samsung SM-S366V / Android 16

Prepare a separate Android record with `--platform android` and the actual
Android package identity. Leave it BLOCKED until existing installation data,
signing identity and secure-storage migration are protected. Do not uninstall,
clear data, use replacement/downgrade install flags, or treat another Android
user as code-level package isolation. The existing `diagnose.py` helpers can
collect read-only package/microphone/crash markers after normal USB authorization.

On a safe disposable installation, repeat startup, local recognition, speech,
interrupt/Stop, background, Safe Mode, restart, planning, journal and consent
checks. Windows Ollama support is not evidence of an Android offline model.
Record unsupported model behavior as BLOCKED; do not substitute a cloud provider
silently. Any explicitly chosen cloud route needs fresh exact-request approval
and its own acceptance record. Measure Android memory/latency on the physical
phone using platform tools; Windows memory evidence does not transfer to it.

## Integration and review

Use one focused PR per reproduced failure. Keep known candidate binaries and
prior results, compare source/bytes, and obtain independent review for privacy,
voice and memory changes. No automatic merge or release acceptance follows from
CI completion. Real-device testing, migration, clinical suitability and public
beta readiness are separate decisions.

The `neura safety` ruleset must target `Neura`, require pull requests, genuine
GitHub Actions baseline checks, up-to-date code, resolved discussions and an
independent approval. Preserve signatures, linear history and deletion/force
push blocks with no bypass actors. A prepared settings page is not enforcement:
verify the saved API state, then the disposable #181 probe without merging it.
Authentication confirmation and physical-device observations require the owner.
