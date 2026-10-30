# Validate Windows speech after PR #144

Start with **Inspect.cmd**. This checks the installed application without
launching it. It does not need administrator access, Python or a new voice.
Requires Windows PowerShell 5.1 (built into supported Windows versions), a local
unpacked Neura bundle, and this whole helper directory extracted **outside**
that bundle. A ZIP or shortcut is not the installed EXE.

1. Double-click **Inspect.cmd** and paste the full path to the actual
   `neuro_companion.exe`. The usual development location ends with
   `build\windows\x64\runner\Release\neuro_companion.exe`.
2. Open the new `Neura-Speech-Results-...` directory beside the helper. Read
   `READ-RESULTS.md`. `speech-evidence.json` contains the filtered evidence.
3. If static inspection fails or is incomplete, stop before speech testing.
   An old bundle, leftover DLL, changed upstream binary format, inaccessible
   file or linked directory requires investigation. Do not delete app data to
   fix inspection. A static fingerprint failure does not itself prove a crash.
4. For supervised audio checks, run **Observe.cmd** on your physical Windows
   PC. The helper displays the scenarios and records only your explicit
   PASS/FAIL/NOT RUN choices and repetition counts. Enter skips a scenario.
   A partial count is recorded as PARTIAL. A failure ends the test session.
   No scenario or whole-device acceptance is inferred from an empty log.
5. Review the JSON before sending it back for investigation. Nothing is
   uploaded automatically. Keep full crash dumps and matching PDBs private.

The helper writes only a new results directory. It never builds, launches or
kills Neura, opens a microphone, changes preferences/permissions/registry/WER,
installs voices, accesses cloud services or copies journals/chats. The CMD files
use a process-only execution-policy override; they do not change system policy.
Run them as your normal Windows user. Do not bypass a managed organization policy.

## What inspection establishes

The EXE is checked for x64 PE metadata and the current native SAPI channel,
fixed native error strings, the Microsoft desktop token restriction and the
`CLSID_SpVoice` identifier. The whole selected bundle is enumerated without
following links. Native EXEs/DLLs are inspected for legacy registration/import
indicators, including renamed native binaries; any nested/case-varied
`flutter_tts_plugin.dll` is rejected. Executables, DLLs, PDBs and the fixed
Flutter AOT/debug payload are hashed to identify the tested bundle. Identity is
checked again after the session to detect an intervening rebuild/replacement.

These are **static fingerprints**, not a signature or reproducible-build
attestation. An arbitrary binary can imitate markers. Static absence does not
prove every possible dynamically loaded module is absent. The exact installed
build's commit remains UNVERIFIED unless separately tied to trusted build
evidence. Configuration and production/harness labels are operator supplied.
Preserve matching symbols and original binaries outside the shared report.

Optionally compare the speech source files with the normalized PR #144 baseline:

```powershell
.\Test-NeuraWindowsSpeech.ps1 -ExePath 'C:\NeuraTest\Release\neuro_companion.exe' -SourceRoot 'C:\src\neura_os' -Configuration Release -EntryPoint Production
```

This source comparison does not establish which source produced the EXE. An
optional `-AppProcessId 1234` inspects modules of an **already running** process
whose main-module path matches the selected EXE. It records only whether SAPI or
the legacy DLL is loaded and the on-disk EXE hash. This is a point-in-time
snapshot, not an in-memory-image hash. Missing access is UNAVAILABLE; no process
is launched or terminated. A loaded legacy module blocks observation mode.

## Use the existing speech tools

Use an isolated Windows test account with synthetic data and no cloud
credentials. Leave microphone, ambient/wake-word listening and automatic
startup greetings off. Prepare dependencies/builds first, then disconnect
networking before audio tests. Never enable the historical boot greeting to
reproduce the crash. Do not test with a profile containing private journals.

The repository already supplies `tools/windows_tts_smoke.dart`, a separate
fixed-text UI using the production `NeuraTtsService` and native SAPI owner. It
has no app startup services, mascot, preferences, AI, journal or microphone.
It offers short/long speech, Stop and Safe Mode. **Do not substitute Voice Lab's
prerecorded clips:** those do not exercise this speech implementation.

The existing [physical acceptance procedure](https://github.com/Vantiger-Construction/neura_os/blob/dd6a53f7bc25f751a48e23087e5040c95125a588/docs/WINDOWS_TTS_RELIABILITY.md#physical-windows-acceptance-not-executed-in-this-investigation)
contains build commands, repetitions, private WER/WinDbg handling and matching
symbol requirements. Reuse it rather than installing a second speech tool.
Run its existing regressions and build in a clean, separate source/output
directory; preserve the old installed bundle for comparison. The helper does
not invoke the Windows launcher, rebuild, remove stale files or download assets.

Run separate Observe sessions against each **production/harness × debug/release**
bundle. Keep the whole bundle and its PDBs together when copying a build. Do not
overwrite one bundle with the other or infer a release result from a debug test.
Use the normal production app for startup with the mascot, fixed voice-preview
disposal and typed offline chat replies. Use the existing harness for controlled
long/short replacement and Stop. It shares the real native owner but cannot
stand in for production chat/mascot acceptance.

Observe covers ten cold launches/first samples, twenty sequential samples,
ten replacements, ten Stop/fresh cycles, ten Safe Mode cycles, ten background/
shutdown cycles, ten production preview-disposal checks, ten typed local chat
replies, and an alternate installed voice/output if available. PASS means you
actually heard the expected speech or silence and saw focus clear; no overlap,
late audio, freeze, timeout or early microphone return occurred. Treat any such
failure as FAIL even if the window recovers. On failure, stop, preserve the exact
bundle and report, and seek focused diagnosis rather than repeatedly crashing.

The manual app session can naturally write synthetic chat/settings in its test
profile. The helper never modifies that profile or the ordinary user's data.
Restore any manual reply-speech setting in the isolated profile afterward.

## Privacy and diagnostic limits

Inspection-only mode reads the last 15 minutes of relevant diagnostics;
Observe mode brackets the supervised session (up to four hours). It reads only
Windows Application events 1000/1001/1002 for `neuro_companion.exe` and the
existing native breadcrumb file `%TEMP%\neura_error_vault.jsonl` plus its three
rotations. It exports only allowlisted timestamps, event types, module labels,
exception codes and relative offsets. Full paths, raw event messages, stack
contents, fault addresses, unrelated Dart log records, arbitrary filenames,
usernames, machine names, speech text, audio and dumps are excluded.

Records without an exact executable path are explicitly name/time associated;
native breadcrumbs are time associated, not bound to a bundle hash. Another
simultaneous Neura process can make attribution ambiguous. Missing, inaccessible
or truncated diagnostics are labeled, and absence of a reported crash is not a
pass. The helper does not configure WER or copy dumps; follow the existing
private crash procedure only when needed and explicitly supervised.

Exit 0 means static preflight and before/after identity completed; it does **not**
mean physical speech passed. Exit 2 means inspection, requested module access or
identity did not pass. Results remain available after those failures. A native
source-line cause still needs the actual faulting binary and matching symbols.
Keep issue #32 open until that evidence and the complete physical matrix have
been reviewed. Keep `kEnableProactiveGreetingTts = false`.

## Helper regression checks

`Test-EvidenceHelper.ps1` uses only synthetic files, fake PE metadata, redacted
event fixtures and simulated keyboard answers. It tests old/missing SAPI,
legacy registration, nested/renamed DLLs, malformed binaries, link rejection,
namespaced Windows event XML, private-field exclusion, missing/denied logs,
source mismatch, result generation and partial/failure recording. No fixture is
executed as a Neura binary. The existing Windows speech workflow runs it using
Windows PowerShell 5.1, alongside the original CMake, Dart and native checks.
