# Windows speech reliability: issue #32

Investigation date: 2026-10-18 UTC. Source baseline:
`a4e8c5e793d4aa3764c66a47819c395b555c786b` (`Neura`).
This work hardens Dart speech lifecycle handling. **The original native access
violation is not verified fixed.** `kEnableProactiveGreetingTts` remains `false`.

## Evidence and corrected diagnosis

| Evidence | Supported conclusion | Limit |
| --- | --- | --- |
| [Issue #32 original report](https://github.com/Vantiger-Construction/neura_os/issues/32) | The initial hypothesis linked first native calls and mascot creation. Several ordering changes reduced reported failures. | Timing correlation did not establish causation. |
| [August 17 debugger report](https://github.com/Vantiger-Construction/neura_os/issues/32#issuecomment-5318685604) | The author reported 10/10 failures with only mascot-required plugins, and 7/8 with mascot creation completely disabled. Dump analysis reported `0xC0000005`, `flutter_tts_plugin+0xe657`, null `rcx`, on the UI thread. | Historical reported experiments; their dumps, binaries and matching symbols were not available for independent re-analysis here. A lifetime/coroutine defect was inferred, not located to a symbolized source line. |
| [Merged PR #38](https://github.com/Vantiger-Construction/neura_os/pull/38) and current `windows/runner/flutter_window.cpp` | The mascot engine registers only window-manager and screen-retriever plugins. Removing duplicate process-global plugin registration is independently useful. | It did not eliminate the crash in the reported isolation tests. |
| [Merged PR #41](https://github.com/Vantiger-Construction/neura_os/pull/41) | Removed `awaitSpeakCompletion(true)` and reused the viseme bridge's terminal callbacks for a Dart completer. | Its verification explicitly excluded interactive Windows playback. Issue #32 is administratively closed, but closure is not device acceptance. |
| [Upstream issue #217](https://github.com/dlutton/flutter_tts/issues/217) | A historical Android 3.0.0 report describes a null method-channel result when using native completion waiting. A commenter proposed Dart completion; the maintainer said they would investigate moving it. | It is not a Windows 4.2.5 reproduction. PR #41 misattributes the proposal to the maintainer and overstates the Windows mechanism. |
| Exact `flutter_tts` 4.2.5 package source | In the Windows desktop branch, `speak()` calls `asyncSpeak(text)` with either setting. The setting controls retaining `speakResult` and calling `Success` on it in stop/completion. `asyncSpeak()` still awaits synthesis, then accesses `mPlayer`; `stop()` closes/replaces that player without canceling the synthesis action. | Source hazards suggest targets for a symbolized investigation. They do not prove which instruction caused the historical crash or that disabling result retention fixes it. |

The inspected package archive is
`https://pub.dev/api/archives/flutter_tts-4.2.5.tar.gz`. SHA-256:
`ce5eb209b40e95f2f4a1397116c87ab2fcdff32257d04ed7a764e75894c03775`,
matching `pubspec.lock`. Relevant file: `windows/flutter_tts_plugin.cpp`, desktop
`addMplayer`, `asyncSpeak`, `speak`, and `stop` (approximately lines 76–140).
Callbacks contain no utterance ID.

The mascot's eager creation completer closes an early-return ordering gap; its
eight-second timeout is a best-effort wait, not a native-subsystem safety gate.
Keep that independent ordering precaution and limited plugin registration. Do
not use them as explanations or fixes for #32. Launch currently avoids native
TTS initialization; explicit voice settings and speech requests initialize it.
Current TTS callers include chat, wake-word replies, jokes, proactive banner
actions and voice-settings previews. The current Voice Lab uses prerecorded
`NeuraVoicePack.playAsset` clips; playing those clips does not test this TTS path.

## Demonstrable Dart defects and bounded correction

Before this change:

- `stop()` did not revoke a `speak()` waiting for initialization. That request
  could speak after chat disposal or after Safe Mode was entered and exited.
- Concurrent requests could both pass `tts.stop()`, replace a shared completer,
  and leave an earlier caller/focus lease waiting indefinitely. A late zero
  result used the global completer rather than the originating utterance.
- Missing completion, or a hung native `speak`/`stop` acknowledgement, had no
  service-level deadline. Audio focus and speaking presence could remain held.
- Voice preview could call `speak` after a pending voice selection outlived a
  stop. Closing voice settings restored a voice without stopping its preview.

The correction uses request/cancellation generations, an ordered native command
tail, and per-utterance completion/lease ownership. Stop revokes pending requests
immediately. A replacement waits for prior command acknowledgement and the stop
barrier; callbacks during that barrier cannot finish the replacement. Completion,
cancel, rejection, error and duplicate signals release their own leases once.
Native errors now fail the Dart speech future rather than looking like successful
speech to callers that might restart a microphone.

Initialization and each command batch have a ten-second deadline; each utterance
has a two-minute completion deadline. Completion timeout attempts a bounded stop
and reports failure. Missing terminal callbacks, unacknowledged commands or failed
stops disable further speech for this service until application restart. Long
utterances can therefore be interrupted at two minutes. The existing twenty-second
streamed-chat caller timeout remains an additional caller boundary.

**Limits:** Dart deadlines do not cancel native coroutines, guarantee silence from
a hung native player, or stop an access violation. Native stop acknowledgement
does not prove synthesis continuations are drained. An old terminal event arriving
after a later utterance has started cannot be attributed reliably because the
plugin supplies no ID. Command-order tests do not establish actual audio ordering.
If physical testing demonstrates this ambiguity, the next change belongs in a
symbolized, separately reviewed native adapter/plugin with utterance IDs and
real synthesis cancellation; do not add another arbitrary startup delay.

Audio focus coordinates only Neura-owned ambient ducking. Its reference counter
does not own the Windows audio session or validate that audio has stopped. Presence
leases are independently revoked by Safe Mode. The viseme bridge remains the sole
callback owner; attachment is tracked per `FlutterTts` object so isolated services
do not retain another object's completion hooks. `FlutterTts` still has one method
channel per isolate: these test instances are not a multi-engine support feature.

The service is normally process-scoped. Isolated service disposal detaches its
Safe Mode listener and invalidates pending speech. Existing chat disposal and
background handling call `stop`; voice settings now also stops a preview before
restoring the selected voice. No microphone, cloud, avatar motion or startup
speech feature is added by this change.

## Automated regressions

`test/services/neura_tts_lifecycle_test.dart` uses a synthetic `FlutterTts` fake
and the actual bridge callback dispatcher. It covers completion before command
return; duplicates/cancel/error/rejection; stop during initialization; Safe Mode
entry/exit; pending/concurrent replacements and late acknowledgement; deadlines;
stop failure; focus/presence release; preview cancellation; reentrant stop; and
service disposal. `test/screens/neura_voice_settings_lifecycle_test.dart` mocks
the TTS method channel and verifies that leaving the screen stops its sample.
No physical sound, microphone, cloud requests or real user content is involved.

Reproduce with the pinned Flutter 3.47.5 / Dart 3.13.4 SDK:

```powershell
flutter pub get
flutter test --no-pub --reporter expanded `
  test/services/neura_tts_lifecycle_test.dart `
  test/screens/neura_voice_settings_lifecycle_test.dart `
  test/services/neura_tts_speak_replies_test.dart `
  test/services/neura_audio_focus_test.dart `
  test/services/neura_companion_presence_test.dart `
  test/neura_link/reply_speech_queue_test.dart `
  test/startup/native_speech_safe_mode_test.dart `
  test/startup/startup_platform_policy_test.dart
```

Local verification on Linux with Flutter 3.47.5 / Dart 3.13.4:

- **46 tests passed** across the eight files listed above (23 new cases).
- Four service regressions and the voice-settings disposal regression failed
  against the original baseline. That reproduction used test-only constructor /
  cleanup seams and per-object bridge attachment, with original speech logic.
- Targeted analysis of all changed Dart files and the harness: no issues.
- Canonical formatting across `lib`, `test` and the harness: no changes required.
- State Matrix YAML parsed; all ten listed test paths exist. Dependency lock and
  disabled greeting flag are unchanged. Windows workflow execution is pending.

The local tests used `--no-test-assets` and `--no-pub`. Dependencies came from
archives verified against the app/SDK locks, with local package configuration;
standard dependency resolution was not claimed. No private app data was used.
Synthetic success is not native Windows acceptance. The new cases are included
in the existing self-hosted State Matrix workflow.

## Physical Windows acceptance (not executed in this investigation)

Only an authorized, interactive **physical Windows** session with working speakers
or headphones can complete these steps. This investigation runs on Linux. An
available self-hosted CI runner is not evidence of permission or ability to hear
and supervise native speech; no remote audio test was dispatched.

Use a clean Windows test account containing synthetic data, microphone/ambient
capture off, and no cloud credentials. Preserve the production entry point and
the disabled greeting flag. Record OS build, audio output/driver, installed voice,
Flutter/Dart versions, plugin version, tested commit and build configuration.
Reserve at least eight GiB plus space for bounded full dumps.

1. Check out the review branch and record `git rev-parse HEAD`. Confirm a clean
   worktree, the locked plugin hash above, and
   `kEnableProactiveGreetingTts = false`. Run the regression commands first.
2. Build the production app (`flutter build windows --debug`). Save the EXE/DLL
   hashes and matching EXE/plugin PDBs if produced. In the normal app, open its
   voice settings and use **Play a sample**: this speaks the fixed synthetic
   sentence already in the app. Observe first-use audio with the normal mascot
   lifecycle. Close voice settings while a sample is playing.
3. For controlled longer speech and explicit Stop/Safe Mode controls, build the
   isolated harness. It uses the same native host/plugin and `NeuraTtsService`,
   with **no mascot**, app startup services, mic, preferences, AI or journal.
   It is a separate diagnostic executable, not the shipping entry point:

   ```powershell
   flutter build windows --debug --target tools/windows_tts_smoke.dart
   ```

   Copy the entire resulting debug bundle to a separate test directory so
   production/harness binaries and their symbols cannot be mixed up. Hash and
   label each bundle. Launch its EXE directly for WER collection rather than
   under `flutter run` or an attached debugger. The harness records only request
   counters, outcome types, Safe Mode and focus state; it cannot certify audible
   completion. Its `completed_or_cancelled` status deliberately distinguishes
   neither outcome. Repeat key scenarios in a release build afterward; retain
   each build's matching symbols where available.
4. Configure diagnostics below before reproduction. Record the test start/end
   UTC times and inspect failures even if a window remains visible.

| Scenario | Minimum repeatable exercise | Required observation |
| --- | --- | --- |
| First user speech, normal production app | Ten cold process launches; voice-settings sample on each, then repeated samples. | Audible first speech, complete expected sentence, no native crash. Startup remains silent. |
| No-mascot isolation harness | Ten cold launches; short then long fixed samples. | Same native speech path remains stable without a second engine. This isolates a hypothesis, not the full app. |
| Replacement during speech/synthesis | Ten long→short replacements, including an immediate second click before audible onset. | No old audio resumes, no overlapping speech, latest request completes, focus clears. |
| Explicit stop and fresh request | Ten long→Stop cycles, then a fresh short request after stop acknowledgement. | Audible silence; no old callback cuts off the fresh request; no stuck focus/ducking. |
| Safe Mode | Enter during first-use initialization and during long speech, then turn off without clicking Speak. Repeat ten times. | Speech stops; no automatic restart; fresh explicit request required. No microphone opens. |
| Background/disposal/close | Minimize during a long sample; close voice settings during its preview; close process immediately after requesting first speech. Repeat ten times. | No resumed old audio, teardown crash or stranded focus. Reopen and explicitly request a fresh sample. |
| Repeated use / output change | Twenty sequential short samples; repeat with installed alternate voice and a controlled output-device change. | No silent success, native error, freeze or stuck speaking/ducked state. Record unavailable devices/voices as untested, not passed. |

Native command or completion timeouts are failures, even if Dart recovers and the
window stays alive. Do not force missing callbacks or change the plugin merely to
make a native acceptance run pass; fault injection belongs in synthetic tests.
For ambient ducking, additionally check a normal Neura-owned ambient player at
its configured level before/during/after the synthetic production preview.

### Crash diagnostics

[Microsoft WER LocalDumps](https://learn.microsoft.com/en-us/windows/win32/wer/collecting-user-mode-dumps)
supports per-executable dump settings. An administrator can configure
`HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\neuro_companion.exe`:

- `DumpFolder` (`REG_EXPAND_SZ`): a writable test-only local directory.
- `DumpCount` (`REG_DWORD`): `3`.
- `DumpType` (`REG_DWORD`): `2` (full dump).

Export any existing per-app key first and record whether it existed. Configure
only this executable; after testing restore the exported settings, or remove only
the newly created per-app key. Do not alter global WER policy. Do not combine WER
with automatic postmortem debugging and assume both captured the same crash.
Full dumps can contain process memory: use only synthetic test sessions and keep
them private. Post a redacted stack/module summary to GitHub, not the dump itself.

Inspect Windows Application log events 1000/1001 for this EXE within the test
interval, and Neura's pass-through native breadcrumb file
`%TEMP%\neura_error_vault.jsonl` plus its rotations. Filter events by executable
and time; an empty log or a still-visible window alone is not a pass. If a crash
occurs, preserve the exact bundle and open its dump in WinDbg with matching
private symbols and Microsoft's public symbols. Capture:

```text
.symfix
.sympath+ C:\path\to\matching\private-symbols
.reload /f
!analyze -v
.ecxr
kv
lmvm flutter_tts_plugin
```

Record exception code, fault module/version/hash, relative offset, thread and
symbolized stack. The historical `+0xe657` offset applies only to its original
binary. If plugin PDBs are unavailable, build the **same locked** plugin in Debug
and reproduce with that matching binary; never apply a different binary's PDB or
claim source-line certainty from an offset alone. If needed, use a separately
recorded first-chance debugger reproduction to inspect synthesis, completion and
stop/player lifetime; keep it separate from the unattached WER acceptance runs.

Record every matrix row as PASS/FAIL/NOT RUN with commit, bundle hashes,
configuration, repetitions, audible result, callback/focus outcome and diagnostic
references. Any crash, late audio, early microphone return, overlap or timeout
blocks acceptance. Attach the redacted result against #32. Keep startup speech
disabled; enabling it needs a later explicit, reviewed startup-specific test and
rollout decision after ordinary native speech acceptance. Do not auto-merge or
infer a native fix from these synthetic regressions.
