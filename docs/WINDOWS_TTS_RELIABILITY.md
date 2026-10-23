# Windows speech reliability: issue #32

Historical investigation date: 2026-10-18 UTC. Source baseline:
`a4e8c5e793d4aa3764c66a47819c395b555c786b` (`Neura`).
Windows speech now uses an owned local SAPI channel instead of the
`flutter_tts` Windows speak/coroutine path. Dart speech ownership is also bounded
and cancellation-aware. **The original native access violation is not verified
fixed on a physical device.** `kEnableProactiveGreetingTts` remains `false`.
Current checkpoint (October 23): [PR #139](https://github.com/Vantiger-Construction/neura_os/pull/139)
and [PR #144](https://github.com/Vantiger-Construction/neura_os/pull/144) are merged.
The latter removes legacy plugin registration/bundling. The [read-only Windows
evidence helper](../tools/windows_speech_validation/README.md) reuses the existing
speech harness; its [evidence record](../tools/windows_speech_validation/VERIFIED_EVIDENCE.md)
separates hosted CI from physical results, which remain NOT RUN.
Issue #32 remains open pending physical Windows acceptance.

## Evidence and corrected diagnosis

| Evidence | Supported conclusion | Limit |
| --- | --- | --- |
| [Issue #32 original report](https://github.com/Vantiger-Construction/neura_os/issues/32) | The initial hypothesis linked first native calls and mascot creation. Several ordering changes reduced reported failures. | Timing correlation did not establish causation. |
| [August 17 debugger report](https://github.com/Vantiger-Construction/neura_os/issues/32#issuecomment-5318685604) | The author reported 10/10 failures with only mascot-required plugins, and 7/8 with mascot creation completely disabled. Dump analysis reported `0xC0000005`, `flutter_tts_plugin+0xe657`, null `rcx`, on the UI thread. | Historical reported experiments; their dumps, binaries and matching symbols were not available for independent re-analysis here. A lifetime/coroutine defect was inferred, not located to a symbolized source line. |
| [Merged PR #38](https://github.com/Vantiger-Construction/neura_os/pull/38) and current `windows/runner/flutter_window.cpp` | The mascot engine registers only window-manager and screen-retriever plugins. Removing duplicate process-global plugin registration is independently useful. | It did not eliminate the crash in the reported isolation tests. |
| [Merged PR #41](https://github.com/Vantiger-Construction/neura_os/pull/41) | Removed `awaitSpeakCompletion(true)` and reused the viseme bridge's terminal callbacks for a Dart completer. | Its verification explicitly excluded interactive Windows playback. The issue was subsequently reopened; its earlier closure was not device acceptance. |
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
not use them as explanations or fixes for #32. Launch avoids Dart service
warm-up and speech. The original SAPI change left the legacy plugin registered at startup. The
October 22 follow-up removes that remaining Windows registration and build
entry using build-local filtered copies of Flutter's regenerated files. The
legacy plugin is neither linked nor bundled; other plugin registrations and
FFI dependencies remain intact. The SAPI voice is created only for explicit
speech. This exclusion does not certify physical native startup/teardown.
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
utterances can therefore be interrupted at two minutes. The existing 45-second
streamed-chat caller timeout remains an additional caller boundary.

The initial lifecycle patch also exposed a full-suite queue scheduling regression,
corrected by lazy, caller-zone queue creation and release after draining (details
below). Stop additionally revokes request generations and returns immediately when
no engine, initialization or playback exists, avoiding unnecessary native dispatch.

**Limits:** Dart deadlines do not interrupt a blocked native UI thread or stop an
access violation. They can release Neura's focus/presence state while a native
operation remains unresponsive. The retained plugin on non-Windows platforms
still supplies untagged callbacks; a very late terminal event cannot reliably be
attributed there. Command-order tests do not establish actual audio ordering.

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

## Windows native speech ownership

`NeuraWindowsTts` implements the existing Dart speech interface over
`neura/speech_synthesis`. The primary Flutter window owns the native channel;
the mascot has no such speech owner. PR #144 excludes the legacy Windows plugin
from registration and bundling using build-local filtered generated files.
Windows service speech/configuration calls use only the owned channel. Missing
channel support fails closed; it never falls back to the legacy plugin.

Each utterance has a monotonically increasing request ID and a fresh `ISpVoice`
COM object/event queue. This second boundary matters:
[SAPI stream numbers restart at 1 when the queue empties](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ee125024(v=vs.85)).
A stream number alone cannot identify a replacement. Stop first revokes the
request, calls SAPI's purge operation, then releases that voice and its queue.
Completion checks both the current owner ID and stream number, and checks the
engine's final HRESULT. Background/minimize/suspend/close also purges the native
owner; teardown releases its channel before the Flutter engine/messenger.

All native channel/COM work stays on the existing UI/STA thread. There are no
native asynchronous continuations capturing the owner, retained method replies,
WinRT synthesis actions or MediaPlayer instances. Dart polls at 40 ms only while
speech is active, with at most one outstanding poll. Polls return only ID/state;
late polls or acknowledgements cannot finish a replacement. Malformed status,
command timeout or failed Stop prevents further adapter speech until restart.
A missing speech acknowledgement requests a bounded best-effort purge. These
bounds cannot force a stalled Windows engine to return.

The catalogue is limited to already-installed Microsoft desktop SAPI tokens
(`Vendor=Microsoft`, `TTS_MS_` IDs); no voice installation, registry modification,
network service, third-party provider or arbitrary default engine is selected.
The catalogue and voice sound can differ from WinRT natural voices. A rejected
saved voice falls back to an eligible local selection without persisting a false
selection. With no eligible installed voice, explicit speech fails. Record that
as unavailable, not as a successful silent utterance.

Rate 0.25–0.75 maps to SAPI -5–5, volume maps to 0–100, and pitch 0.5–2 maps
logarithmically to SAPI XML absolute pitch -10–10. Text is bounded to 64 KiB of
strict UTF-8, rejects NUL, and is escaped inside the controlled pitch element.
User input cannot create XML/audio/file directives. The current utterance exists
only in process memory; channel errors contain static descriptions, not text.
The older untagged-plugin limitation is avoided by this Windows owner, but an
OS speech-engine defect can still crash the process. Native acceptance is required.

## Automated regressions

`test/services/neura_tts_lifecycle_test.dart` uses a synthetic `FlutterTts` fake
and the actual bridge callback dispatcher. It covers completion before command
return; duplicates/cancel/error/rejection; stop during initialization; Safe Mode
entry/exit; pending/concurrent replacements and late acknowledgement; deadlines;
stop failure; focus/presence release; preview cancellation; reentrant stop; and
service disposal. `test/screens/neura_voice_settings_lifecycle_test.dart` mocks
the TTS method channel and verifies that leaving the screen stops its sample.
Two process-scoped queue cases construct the service outside the widget clock
and use it from consecutive widget clocks. The existing voice-command and offline
chat suites exercise the same stop barrier through real screen interactions.
No physical sound, microphone, cloud requests or real user content is involved.

`test/services/neura_windows_tts_test.dart` adds 14 method-channel regressions for
request identity, late polls/acknowledgements, background cancellation, malformed
status, bounded poll/speak acknowledgement, failed Stop, text/concurrency bounds,
missing owner and settings routing. Every test rejects legacy plugin invocation.
Explicit Stop still emits the existing cancellation/rest callback exactly once;
an old Stop acknowledgement cannot emit that callback for a replacement.
An inbound-channel regression also proves that legacy plugin events cannot
terminate owned Windows speech. It failed against `559e371` (completion, cancel
and error each fired), then passed after overriding the inherited legacy event
dispatcher. Only the owned channel's request-matched status may finish speech.
`neura_windows_tts_routing_test.dart` verifies the actual Windows service selects
the local owner and that Safe Mode blocks initialization/speech. The portable
native contract checks 17 ownership/escaping assertions, including reused stream
numbers with different owners. It does not instantiate COM or execute speech.

Reproduce with the pinned Flutter 3.47.5 / Dart 3.13.4 SDK:

```powershell
flutter pub get
flutter test --no-pub --reporter expanded `
  test/services/neura_tts_lifecycle_test.dart `
  test/modules/chat/neura_voice_commands_test.dart `
  test/modules/chat/neura_offline_chat_test.dart `
  test/services/neura_windows_tts_test.dart `
  test/services/neura_windows_tts_routing_test.dart `
  test/screens/neura_voice_settings_lifecycle_test.dart `
  test/services/neura_tts_speak_replies_test.dart `
  test/services/neura_audio_focus_test.dart `
  test/services/neura_companion_presence_test.dart `
  test/neura_link/reply_speech_queue_test.dart `
  test/startup/native_speech_safe_mode_test.dart `
  test/startup/startup_platform_policy_test.dart
```

Current verification uses Linux with Flutter 3.47.5 / Dart 3.13.4:

- The first Dart-only patch passed 46 focused tests, but its subsequent hosted
  full-suite run exposed 26 failures (809 passed) in chat/voice tests. The no-op
  Stop correction above then passed all 835 tests before adding the native owner.
- **852/852 tests passed** in the complete Flutter suite after integrating the
  Windows owner and both process-scoped queue regressions from `f20c873`:
  `flutter test --no-pub --coverage --reporter expanded --concurrency 4`.
- Four service regressions and the voice-settings disposal regression failed
  against the original baseline. That reproduction used test-only constructor /
  cleanup seams and per-object bridge attachment, with original speech logic.
- Targeted analysis of all changed Dart files and the harness: no issues.
- Canonical formatting across `lib`, `test` and the harness: no changes required.
- The actual Windows owner cross-compiles with MinGW 13.2 against genuine Flutter
  3.47.5 wrapper headers with warnings treated as errors. This is not an MSVC,
  whole-application, runtime or acoustic acceptance result.
- The pure native contract passes all 17 assertions under Linux g++ with
  `-std=c++17 -Wall -Wextra -Werror -pedantic`.
- Hosted [Windows checks at `007020f`](https://github.com/Vantiger-Construction/neura_os/actions/runs/39099927303)
  passed locked dependency restoration, analysis, all 70 selected Dart cases,
  MSVC 19.51 compilation/linking of the real owner with genuine Flutter SDK
  sources/libraries, and the pure native contract. The complete hosted Flutter
  coverage and both Rust coverage jobs also passed at that commit. The follow-up
  [Windows run at `559e371`](https://github.com/Vantiger-Construction/neura_os/actions/runs/39100381454)
  passed all 72 selected Dart cases, real-owner compile/link under the production
  `_HAS_EXCEPTIONS=0` setting, and the native contract. Head-specific results are
  recorded on PR #139 and issue #32; none of these jobs executes speech.
- Dependency lock and disabled greeting flag are unchanged.

The full local suite uses normal test assets, `--no-pub`, `--coverage`, and
concurrency 4. Dependencies came from
archives verified against the app/SDK locks, with local package configuration;
standard dependency resolution was not claimed. No private app data was used.
Synthetic success is not native Windows acceptance. All new Dart cases are in
the existing self-hosted State Matrix workflow. The dedicated hosted Windows
workflow `.github/workflows/neura-windows-tts.yml` additionally compiles/links the
real owner with genuine Flutter wrapper/API sources and the Windows import
library, then executes only the pure ownership/escaping assertions. It discovers
SDK paths instead of assuming wrapper headers are under the engine cache.
It never instantiates a speech voice, opens a microphone or runs the app.

### Complete-suite chat queue regression

The [initial coverage run](https://github.com/Vantiger-Construction/neura_os/actions/runs/39098375562)
at `c96bfb0` passed 809 Flutter tests and failed 26 voice-command/offline-chat
tests. Both Rust coverage jobs passed. The same 26 failures reproduced locally:
commands and offline-session selection awaited `stop()`, whose queue dispatched
only after the widget assertions had finished. The constructor-created completed
future retained its outer zone's scheduler, outside the widget test clock.

The native tail now starts lazily in the calling zone and clears after draining,
only if no newer command owns the tail. This preserves ordering, deadlines,
generation invalidation and native-failure quarantine while avoiding an idle
queue tied to the service's construction or a previous test's clock. No extra
pumps, sleeps, microphone restarts or relaxed expectations were added to the chat
tests. The two process-scoped regressions cover initial dispatch and reuse across
widget clocks; both chat suites now also run in the Windows State Matrix.

Earlier queue follow-up verification at `f20c873` on Linux with Flutter 3.47.5 /
Dart 3.13.4 (before the Windows native owner):

- **837/837 tests passed** in the complete Flutter suite with coverage, using
  `--no-pub --no-test-assets --concurrency 2 --timeout 2m`. The local test asset
  bundle was already built; this does not claim a fresh asset build.
- All 33 tests in the two affected chat files passed, together with the original
  22 lifecycle cases; all 24 lifecycle cases passed after adding the two queue
  regressions. Both new queue assertions fail against the original `c96bfb0`
  implementation; that reproduction was stopped at its external 90-second bound
  while the original queue remained stuck during teardown.
- Targeted analysis: no issues. Canonical formatting: 632 files, zero changes.
  State Matrix YAML parsed and all 15 referenced test paths exist.
- Dependency manifests, native code, startup speech policy and chat test
  assertions are unchanged. Fresh GitHub/Windows validation remains separate.

## Physical Windows acceptance (not executed in this investigation)

Only an authorized, interactive **physical Windows** session with working speakers
or headphones can complete these steps. This investigation runs on Linux. An
available self-hosted CI runner is not evidence of permission or ability to hear
and supervise native speech; no remote audio test was dispatched.

Use a clean Windows test account containing synthetic data, an installed eligible
Microsoft desktop voice, microphone/ambient capture off, and no cloud credentials.
Disconnect networking for the synthetic playback runs. Preserve the production entry point and
the disabled greeting flag. Record OS build, audio output/driver, installed voice,
Flutter/Dart versions, plugin version, tested commit and build configuration.
Reserve at least eight GiB plus space for bounded full dumps.

1. Check out PR #144's merged commit or a later reviewed build and record
   `git rev-parse HEAD`. Confirm a clean
   worktree, the locked plugin hash above, and
   `kEnableProactiveGreetingTts = false`. Run the regression commands first.
2. Build the production app (`flutter build windows --debug`). Save the EXE/DLL
   hashes and matching EXE/plugin PDBs if produced. In the normal app, open its
   voice settings and use **Play a sample**: this speaks the fixed synthetic
   sentence already in the app. Observe first-use audio with the normal mascot
   lifecycle. Close voice settings while a sample is playing.
3. For controlled longer speech and explicit Stop/Safe Mode controls, build the
   isolated harness. It uses the same native SAPI owner and `NeuraTtsService`,
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
lmvm neuro_companion
lmvm sapi
```

Record exception code, fault module/version/hash, relative offset, thread and
symbolized stack. The historical `+0xe657` offset applies only to its original
binary. Inspect the actual fault module with `lmvm <module>`; use
`lmvm flutter_tts_plugin` if that module appears in a new failure or when analyzing
the historical bundle. Never apply a different binary's PDB or claim source-line
certainty from an offset alone. If needed, use a separately recorded first-chance
debugger reproduction to inspect SAPI creation, completion, purge and teardown;
keep it separate from the unattached WER acceptance runs.

Record every matrix row as PASS/FAIL/NOT RUN with commit, bundle hashes,
configuration, repetitions, audible result, callback/focus outcome and diagnostic
references. Any crash, late audio, early microphone return, overlap or timeout
blocks acceptance. Attach the redacted result against #32. Keep startup speech
disabled; enabling it needs a later explicit, reviewed startup-specific test and
rollout decision after ordinary native speech acceptance. Do not auto-merge or
infer a native fix from these synthetic regressions.

## October 22 follow-up: remove the remaining legacy Windows plugin

PR #139 merged as `7402f3ab9135ae49b96f1f3b126e2e6b07ed95ee`. The old issue
checkpoint describing it as draft is historical. The default Windows service
already routes speech through `NeuraWindowsTts` and the local SAPI owner.

`windows/cmake/NeuraWindowsPlugins.cmake` now prepares build-local copies of
the generated registrant and plugin list, excluding only `flutter_tts` on
Windows. Flutter regeneration cannot silently reintroduce its constructor,
registration or bundled DLL. An unfamiliar upstream TTS registration/build
shape fails configuration for review. The generated source files, Android and
other platforms retain their normal dependencies; no timing delay, greeting
enablement or legacy speech fallback is added.

The three executable CMake fixture regressions verify regeneration, all other
plugin/FFI registrations, changed-format rejection and CRLF input. Hosted
Windows speech CI additionally builds the complete app and rejects any
`flutter_tts_plugin.dll` in the fresh output. Those build checks do not run
actual speech. Use a clean Windows output directory when manually validating
so stale DLLs from an older build cannot contaminate the result.

### Immediate workaround on an already installed build

In **Voice Settings → Automatic reply speech**, choose **Off** to keep chat
replies as text. Avoid explicit Speak/sample/preview actions while diagnosing
speech. This setting controls automatic chat replies; it is not a global mute
for every explicit speech command. If you need a restricted no-microphone
session, use Safe Mode and keep voice/wake-word listening off. Startup greeting
remains disabled. Use installed Microsoft desktop SAPI voices for deliberate
testing after updating; the old WinRT voice catalogue need not match.

Keep issue #32 open until debug/release physical Windows acceptance records
first-use and repeated playback, Stop/replacement, Safe Mode, background/close,
normal mascot lifecycle and matching bundle/dump evidence. The historical
plugin source-line root cause is unproven; this change removes its Windows
load path rather than claiming that the old library itself was repaired.
