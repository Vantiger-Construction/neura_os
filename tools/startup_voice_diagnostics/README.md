# Startup voice diagnostic kit

For the current Windows-first conversation trial, RAM sampler and fixed-build
evidence rules, start with [Windows-first acceptance](../../docs/WINDOWS_FIRST_ACCEPTANCE.md).
The #161/#177 catalog below is historical startup evidence; it does not select
the current hands-free conversation candidate or establish device acceptance.

Start with an empty Android emulator and a separate Windows test account.
Use synthetic data only. The helpers inspect files and collect filtered metadata;
they never install, launch Neura, activate speech/microphones, change permission,
clear data, change keys, wipe, download models or upload evidence.

The observed Windows laptop and Samsung SM-S366V / Android 16 results are still
**NOT RUN**. Installing a new APK on the Samsung is **BLOCKED** until its existing
data and installation state can be protected. A build or emulator result cannot
be substituted for physical-device acceptance.

## 1. Select and verify one build

Inspection date: November 6, 2026. All times in evidence are explicitly UTC.
The default branch snapshot is `6523cbe50490613dbb68b2a4d35cfa704efc2fd2`,
tree `e265bb295afa3480bdc9e97501a5d6ba1655366f`.

| Build | Purpose | Packaged source | Android application/version |
| --- | --- | --- | --- |
| `161-*` | Original merged startup-voice baseline | `e8d99229321a025d2c3f3a2ab173e489b1343195` | `com.neurocompanion.app`, 1.5.1, code 596 |
| `177-*` | Newer merged application; its packaged tree matches the inspected default branch | `a4796a3a637a254a71f8dcf0b6eae96f521f0c70` | `com.neurocompanion.app`, 1.5.1, code 607 |

The PR #161 merge itself is `6aa37404e81fd2ee33d160997c78e5045bae0b55`.
PR heads, packaged PR merge commits, final default-branch merge commits and trees
are different identifiers. Do not label the PR artifact as a build of the final
merge commit. This kit records each separately. The byte hashes and exact asset
URLs are pinned in `build-catalog.json`; see `AUTOMATED_RESULTS.md` for findings.
Newer open-PR packages were visible in the release inventory; they are not the
selected merged-source baseline and have no device acceptance in this kit.

Download all **three** assets for one platform from the matching release:

- [PR #161 packages](https://github.com/Vantiger-Construction/neura_os/releases/tag/neura-ci-pr-161-d6edfbc90bc6-e8d99229321a)
- [PR #177 packages](https://github.com/Vantiger-Construction/neura_os/releases/tag/neura-ci-pr-177-9fd4011c47cb-a4796a3a637a)

Keep their exact names in `C:\NeuraVoicePackages\177` (or another new folder).
They are the binary, `*-build-manifest.json` and `*-SHA256SUMS.txt`. The ZIP
contains this kit, not replacement application binaries or an installer.

From this directory in PowerShell, with Python 3.10+ installed:

```powershell
New-Item -ItemType Directory -Path .\evidence
python .\diagnose.py verify-package --build 177-windows --directory C:\NeuraVoicePackages\177 --output .\evidence\177-windows-package.json
python .\diagnose.py verify-package --build 177-android --directory C:\NeuraVoicePackages\177 --output .\evidence\177-android-package.json
Get-FileHash -Algorithm SHA256 -LiteralPath 'C:\NeuraVoicePackages\177\NeuraCompanion-Windows-9fd4011c47cb-42163332979-1.zip'
Get-FileHash -Algorithm SHA256 -LiteralPath 'C:\NeuraVoicePackages\177\NeuraCompanion-Android-9fd4011c47cb-42163332861-1.apk'
```

Use `161-windows` / `161-android` and their own asset folder for baseline checks.
Every output name must be new. Exit 0 means that helper's limited check completed;
exit 2 means failure or blocked collection. Neither means physical acceptance.
The verifier checks the trusted catalog hashes/lengths, exact manifest identity,
both checksum targets, ZIP paths/duplicates/links, CRCs and every payload hash.
It reads archives without extracting or executing them. Windows checks also
require the x64 PE and release payload and reject the legacy TTS DLL. This is
release-byte identity, not a reproducible-build or Authenticode attestation.

With JDK 17 and Android SDK Build-Tools 36.0.0 already installed, verify the APK
signature, application, version and microphone permission without any device:

```powershell
$BuildTools = "$env:LOCALAPPDATA\Android\Sdk\build-tools\36.0.0"
$Apk = 'C:\NeuraVoicePackages\177\NeuraCompanion-Android-9fd4011c47cb-42163332861-1.apk'
java -jar "$BuildTools\lib\apksigner.jar" verify --verbose --print-certs "$Apk"
& "$BuildTools\aapt.exe" dump badging "$Apk" | Select-String "^package:|^sdkVersion:|^targetSdkVersion:|android.permission.RECORD_AUDIO"
python .\diagnose.py apk-identity --build 177-android --directory C:\NeuraVoicePackages\177 --java java --apksigner-jar "$BuildTools\lib\apksigner.jar" --aapt "$BuildTools\aapt.exe" --output .\evidence\177-apk-identity.json
```

The SDK Command-Line Tools alternative is:

```powershell
$Analyzer = "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\apkanalyzer.bat"
& $Analyzer apk summary "$Apk"
& $Analyzer manifest permissions "$Apk"
```

These are supported SDK commands; install missing SDK tools separately through
Android Studio, not by running an unknown installer. On Linux, use the SDK's
`aapt` and `lib/apksigner.jar`; the Linux build-tools may require their adjacent
`lib64` directory on the loader path. Do not modify the APK or re-sign it.

## 2. Protect existing installations

**Android update gate:** #161's packaged lockfile resolves `flutter_secure_storage`
10.3.1; the newer #177/default tree resolves 11.2.0. The migration documentation
still requires an exercised v10 stage for older v9 stores. Neither these package
checks nor the older dependency version establishes that migration.
`resetOnError: false` and migration options are present,
but they do not establish a validated v9-to-v11 upgrade path. Existing journals,
credentials and encrypted memories must stay on their original installation.
A copied database or untested encrypted backup is not proof that its device-bound
key can be restored. This kit never exports or reads those keys or stores.

The two APKs also have different disposable debug certificates (listed in the
catalog). Even a matching certificate would not remove the migration block.
Do not use `adb install -r`, downgrade flags, uninstall, `pm clear`, backup reset,
keystore deletion or signature-bypass tools to resolve an update failure.

Use a newly created, single-user Android 16 / API 36 AVD with no restored data or
accounts. About 2 GiB guest RAM is a practical starting point for the <=8 GiB
laptop; run no local model alongside it. Missing on-device ASR/TTS on an emulator
is **BLOCKED**, not a reason to enable online recognition or download a model.
An emulator can check installation and failure behavior, not Samsung hardware.

A second Android user, work profile or Samsung Secure Folder is not sufficient
assurance for updating the same application ID: Android package code/signing can
be shared between users. Keep the Samsung unchanged. For later physical testing,
use a genuinely disposable handset or a separately reviewed build with a distinct
application ID and independent storage. That would be a different build identity.

**Windows isolation:** a new ZIP folder alone does not isolate app data. Use a
separate standard local Windows test account with an empty profile and no cloud
credentials, journals or imported vault. Keep the original Windows bundle and
account intact. Download dependencies beforehand; disconnect networking for the
initial speech tests. Do not start an installer that replaces the normal app.

## 3. Windows prerequisites and diagnostics

Run in **64-bit Windows PowerShell 5.1** as the isolated test user:

```powershell
powershell.exe -NoLogo -NoProfile -File .\Test-WindowsPrerequisites.ps1 -OutputFile .\evidence\windows-prerequisites.json
```

This enumerates Microsoft tokens through SAPI's token category only. It creates
neither `SpVoice` nor a recognizer. Eligible input IDs start with `MS-` and contain
`-DESK`; eligible output IDs start with `TTS_MS_`. It also reads advisory microphone
privacy values. An empty or inaccessible catalog blocks testing. Do not edit
registry tokens or enable Windows online dictation to make a check pass.

Manually confirm Settings > Privacy & security > Microphone allows the intended
desktop app, and Settings > System > Sound shows the intended mic/speaker.
Record local language packs and the selected output voice, not device serials.
Finding tokens does not test hardware, language compatibility, audible completion
or microphone permission enforcement. Keep ambient/wake-word capture off.

Extract the verified application ZIP into a new folder **inside that test
account**. Launch `neuro_companion.exe` manually, retaining the full bundle.
Do not use `--launch-smoke-test`: its sentinel exits before Flutter UI startup.
For package hashes and allowlisted crash events, reuse the included repository
helper (from this directory):

```powershell
powershell.exe -NoLogo -NoProfile -File ..\windows_speech_validation\Test-NeuraWindowsSpeech.ps1 -ExePath 'C:\NeuraVoiceTest\Release\neuro_companion.exe' -OutputParent .\evidence -Configuration Release -EntryPoint Production
```

Run once before the matrix and again immediately after a failure or test block.
Use only its inspection mode. Its historical `-Observe` checklist keeps startup
off and is not this startup-voice acceptance procedure. The inspected source
baseline in that helper is historical; this kit's package report supplies the
current binary provenance. Keep the helper/output outside the application bundle.

It filters the recent 15 minutes of Application events 1000/1001/1002 and native
breadcrumbs into timestamps, crash classes/module labels and exception metadata.
No raw event, transcript, account, path, journal or dump is exported. Time/name
association can be ambiguous if another Neura process is running. Missing logs
or a still-visible window never establish a pass. Keep full dumps and matching
symbols private; WER/registry configuration is not part of this kit.

## 4. Android: read-only inspection, then a disposable first install

Enable USB debugging only when you intentionally want this connection. Run
`adb devices -l` locally and choose an explicit serial; do not share that output.
All helper reports use an operator-chosen synthetic alias instead of the serial.

```powershell
$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $Adb devices -l
$Serial = 'emulator-5554'
& $Adb -s $Serial shell am get-current-user
& $Adb -s $Serial shell pm list users
& $Adb -s $Serial shell pm list packages -u com.neurocompanion.app
python .\diagnose.py android-snapshot --adb "$Adb" --serial "$Serial" --user 0 --alias avd-synthetic --label before --output .\evidence\avd-before.json
```

The same snapshot command can inspect the Samsung using its actual local serial
and current user number. It changes no permission, state or data. A missing app,
unavailable command or absent local engine does not pass acceptance. Version code
596 or 607 alone does not bind an installed binary to these APKs.

Optional installed-code certificate comparison, without reading app data:

```powershell
& $Adb -s $Serial shell pm path --user 0 com.neurocompanion.app
# If present, copy only the returned base.apk path into the next command.
& $Adb -s $Serial pull '/data/app/EXACT_RETURNED_PATH/base.apk' .\installed-base.apk
java -jar "$BuildTools\lib\apksigner.jar" verify --print-certs .\installed-base.apk
Get-FileHash -Algorithm SHA256 .\installed-base.apk
```

Do not guess the path or pull a data/keystore directory. Keep the code copy
local. A split installation may require separate split identity checks.
Certificate/hash comparison is read-only and never authorizes an update.

Only on the fresh AVD, after package and APK-identity checks pass:

```powershell
python .\diagnose.py emulator-install-command --build 177-android --directory C:\NeuraVoicePackages\177 --adb "$Adb" --serial emulator-5554 --user 0 --output .\evidence\avd-first-install-command.json
# Review that report: it only prints a command, and refuses physical devices,
# other users, multiple users and an existing/retained package.
& $Adb -s emulator-5554 install --user 0 "$Apk"
```

Run that final install line manually only for the confirmed empty, disposable
AVD. There is deliberately no replace flag. If installation fails, record the
failure category and stop; do not remove any existing app. After success rerun
`android-snapshot` with a new output name and confirm app/version/user. The APK
must remain byte-identical to the verified file. No Samsung install is performed
by this procedure.

## 5. Reproduce startup and capture bounded, filtered evidence

Start a collector **before** launch in terminal A. It follows system/crash tags
as well as app errors, learning Neura PIDs from package-associated lines, so an
early startup crash is not lost merely because `pidof` returns empty:

```powershell
python .\diagnose.py android-capture --adb "$Adb" --serial "$Serial" --alias avd-synthetic --seconds 45 --output .\evidence\cold-start-markers.json
```

In terminal B, only in the disposable test installation:

```powershell
& $Adb -s $Serial shell am force-stop --user 0 com.neurocompanion.app
& $Adb -s $Serial shell am start -W --user 0 -n com.neurocompanion.app/.MainActivity
python .\diagnose.py android-snapshot --adb "$Adb" --serial "$Serial" --user 0 --alias avd-synthetic --label foreground --output .\evidence\foreground.json
```

`force-stop` ends the test process without clearing data. Close normally before
using it when possible. `am start` success or timings do not prove a rendered UI:
observe the dashboard and voice route. Record a persistent blank screen as FAIL,
with OS build, build identity and the filtered marker report. Stop after a crash.

Repeat the snapshot during listening, after Stop, after Home/lock, after resume
and in Safe Mode; use unique names/labels. Underlying read-only commands are:

```powershell
& $Adb -s $Serial shell cmd appops get --user 0 com.neurocompanion.app RECORD_AUDIO
& $Adb -s $Serial shell dumpsys package com.neurocompanion.app
& $Adb -s $Serial shell dumpsys audio
& $Adb -s $Serial shell cmd package query-services --brief --user 0 -a android.speech.RecognitionService
```

Those raw commands are for local inspection only. Share the helper's reports:
it exports the selected user's RECORD_AUDIO grant, app-op mode/running marker,
version, audio-reference counts and service count, never the raw dumps. Historical
app-op times and audio-reference counts are not active-mic proof. Recognition
may run inside a separate service UID. Combine snapshots with Android's current
microphone indicator/Privacy Dashboard and supervised observations. A service
listing does not establish `isOnDeviceRecognitionAvailable`, nor identify an
installed offline output voice. The app's availability check and airplane-mode
exercise are required. Permission-denied dumpsys access is BLOCKED.

The log collector retains at most 4,000 lines in RAM, each at most 2,048 bytes,
and writes only allowlisted event classes. It never saves raw logcat or clears
the global log buffer. Truncation, early exit, missing associations or no records
reduce evidence; none is a pass. Do not collect a global bugreport, transcript,
screen/audio recording, shared app-data archive, packet payload or decrypted TLS.

## 6. Observe the acceptance matrix

Use Settings > Neura's Voice > Voice on startup. Begin with it off. Enabling it
requires local engines and, on Android, microphone permission; it can select
After reply if reply speech was off. **Start voice now** uses the same path.
After sign-in/device-lock gates, the expected complete greeting is:
“Hi, I'm Neura. I'm here and ready to listen.”

Use the fixed phrase “The blue folder is on the table.” Record only whether
the visible phrase matched and appeared once; no spoken/private text belongs
in evidence. Recognition does not require a successful model reply. Keep models
explicitly selected, within existing admission limits, and never download one
for this test. Ordinary legacy mic/Voice Journal paths are separate; use the
startup voice route, not an unrelated recognizer or prerecorded Voice Lab clip.

Run the startup off/on/order/local phrase checks on three cold launches per
device/build. Exercise each interruption once during greeting and once during
listening; record each attempt separately. These are minimum diagnostics, not a
reliability certification. Stop at a demonstrated failure rather than repeating
crashes or allowing uncertain microphone activity.

| Record ID | Reproducible exercise | Required observation |
| --- | --- | --- |
| isolation_and_build_identity | Verify bundle/APK, source/tree, user/profile and installed code hash. | Exact identity and disposable data confirmed; otherwise BLOCKED. |
| cold_start_opt_out | Leave startup off; close and cold launch three times. | Dashboard works; no greeting/capture. |
| permission_denied | On fresh Android, deny the permission requested while enabling startup; on isolated Windows test account, deny desktop mic access in OS settings and try. | Text remains usable; no capture or online fallback. If no local engine lets you reach the permission path, BLOCKED. Restore only the test user's setting afterward. |
| permission_dialog_resume | Android: grant/deny in the prompt, background/return, then wait. | No silent capture after dialog/focus transition; fresh explicit action needed. Windows: BLOCKED if no equivalent dialog exists. |
| cold_start_opt_in | Explicitly enable, close, cold launch after prerequisites. | One foreground voice route and one greeting per process after lock/sign-in gates. |
| greeting_before_mic | Listen to the entire greeting and watch app/OS mic state on all three cold launches. | Mic remains off until audible completion; never submits its own greeting. Record ordering observation, not inferred callback success. |
| one_local_phrase | After the listening indicator appears, speak the fixed phrase once. | Exactly one matching visible submission, with capture stopped before reply; record count/match only. |
| airplane_or_disconnected | Disconnect Windows networking; Android airplane mode with Wi-Fi/mobile data off. Repeat order/phrase. | Local greeting/recognition works or fails closed; no fallback/download. Offline prevention does not prove no attempted requests when online. |
| missing_local_engine | Use a separate fresh AVD without local ASR or offline TTS; do not remove installed packs from a valued device. | Explicit unavailability, usable text and mic off. If unavailable scenario cannot be arranged safely, BLOCKED. |
| stop_during_greeting | Use End hands-free conversation/Stop before greeting finishes. | Audio ends; mic never starts afterward; no late submission. |
| stop_during_listening | Press Stop; say a fixed phrase afterward; wait 10 seconds. | OS capture ends; no late text; fresh action required. |
| mute_or_interruption | Mute during greeting; separately interrupt an audible reply. | Incomplete/cancelled greeting must not start mic; old audio must not resume. Reply mute controls output, not microphone consent: use Stop to end capture. |
| route_cover_and_close | Cover chat with another opaque route, then close/back from chat; repeat in both phases. | Capture/session ends and stale events are ignored. Approval dialogs remain part of their active request and are a separate case. |
| background_during_greeting | Windows Alt-Tab/minimize; Android Home/task switch before greeting ends. | No late mic start; no old audio/text on resume. |
| background_during_listening | Repeat while listening; take before/after snapshots. | OS mic activity ends; no background transcript or silent restart. |
| lock_or_suspend | Lock Windows / safely suspend the test session; lock Android. | Capture ends; unlock does not silently resume. Mark suspend BLOCKED if not safely testable. |
| resume_without_gesture | Return after each interruption; wait 10 seconds without touching mic. | Mic stays off; only explicit mic/Start voice now can begin a fresh session. |
| startup_opt_out | Disable startup in Voice settings; cold launch again. | Saved opt-out survives relaunch; no speech/capture; existing journals remain untouched. |
| permission_revoked | Revoke mic using the test app's OS permission page; return/relaunch. | Text available, no capture, no stale results; no automatic grant. Do not use blanket app-op resets. |
| silence_or_recognizer_error | Stay silent 20 seconds; repeat on a disposable environment with an unavailable local service. | No empty/duplicate send or stuck capture after Stop/error; resume requires an explicit gesture. Record platform silence behavior, not an assumed universal timeout. |
| safe_mode_during_greeting | Open Diagnostics during greeting, enable Safe Mode, then try voice. | Mic off, no pending greeting can start it; voice remains blocked. Opening Diagnostics already covers chat: note this confound. Direct in-flight Safe Mode delivery is BLOCKED unless a supported independent control is available. |
| safe_mode_during_listening | Repeat from listening; attempt Start voice now in Safe Mode and restart as UI requires. | Capture off, no automatic speech/cloud work, no silent resume. Note route-cover confound separately. |
| recovery_restart_required | If the actual recovery/restart-required UI is available, enter it and try voice. | Mic off; stale completion ignored; explicit restart required. No supported trigger: BLOCKED, with synthetic CI recorded separately. Do not corrupt preferences or provoke crashes. |
| cloud_approval_cancel | In the foreground, select an existing cloud route; submit only a synthetic request and cancel its exact-request dialog. | Startup consent never authorizes dispatch. Record dialog and cancellation; request non-dispatch requires independent dispatch/network evidence below. No available configured route: BLOCKED. |
| no_background_cloud | Repeat Home/lock/Safe Mode around a pending synthetic cloud approval; do not approve. | No provider dispatch, automatic fallback or download; no background voice. Missing dispatch evidence: BLOCKED. |
| memory_consent_unchanged | Inspect test-profile permissions before/after startup, without enabling memory or importing journals. | No new recall, remembering, ambient or wake-word permission; no automatic journal import. |
| disposable_wipe_shutdown | Last, only with disposable synthetic data, use the app's full-data-removal flow while voice is active; read success/failure UI and observe mic shutdown. | Capture ends; no late text; opt-in is removed on relaunch. A reported failure stays incomplete. This tests the voice barrier, not recovery of real keys. If no active session can reach the wipe dialog, record the coverage limit. Never run on the valued installations. |

For connected cloud rows, a dialog screenshot or empty filtered log is not proof
that nothing was sent. Use an already approved, app/process/UID-scoped network or
request-dispatch observer that retains only time, destination category and request
counts. Do not add credentials, change a provider to bypass approval, install TLS
interception, capture payloads or upload packets. Distinguish model-provider calls
from the packages' configured Supabase backend/auth traffic and loopback Ollama.
If such an observer is unavailable, record the UI outcome but mark the no-dispatch
portion BLOCKED. The kit intentionally does not introduce a network interceptor.
An actual unintended request, early mic start, late text/audio, native crash or
unconfirmed shutdown is FAIL and blocks acceptance.

## 7. Keep one honest evidence record per device and build

```powershell
python .\diagnose.py new-record --build 177-windows --alias laptop-test-account --output .\evidence\laptop-record.json
python .\diagnose.py new-record --build 177-android --alias samsung-synthetic --output .\evidence\samsung-record.json
```

Fill only observations you performed: exact OS/build, recognizer language, offline
voice, network condition, repetition count, UTC time and synthetic observer alias.
Copy source/tree and APK/ZIP SHA-256 from the package report. Bind installed code
to it (Windows EXE/data hashes; Android pulled base APK hash/certificate, accounting
for any splits) before setting `installed_identity_verified` true.

Use **PASS** for all required observed conditions, **FAIL** for a deviation,
**BLOCKED** for an unsafe/missing prerequisite or unavailable required evidence,
and **NOT RUN** for untouched work. Do not convert an unavailable engine to an
overall pass because it failed closed. Leave overall acceptance incomplete until
all applicable rows and diagnostic limitations have been reviewed. Never merge
AVD, Windows and Samsung observations into one device pass.

Reference sanitized relative filenames, for example
`foreground.json`, `after-stop.json`, `cold-start-markers.json`, and the existing
Windows helper's `speech-evidence.json`. Keep package evidence under
`automated/` and physical observations under `device/`. Review every file before
sharing. No report is uploaded automatically. Retain original code/symbols privately;
omit usernames, serials, machine names, raw audio, real transcripts, account IDs,
keys, credentials, databases, raw logs and dumps from shared records.

## Sources and automated regression commands

- [Startup acceptance contract](https://github.com/Vantiger-Construction/neura_os/blob/6523cbe50490613dbb68b2a4d35cfa704efc2fd2/docs/STARTUP_VOICE.md)
- [Configured packages and signing warning](https://github.com/Vantiger-Construction/neura_os/blob/6523cbe50490613dbb68b2a4d35cfa704efc2fd2/docs/CONFIGURED_BUILDS.md)
- [Storage migration documentation](https://github.com/Vantiger-Construction/neura_os/blob/6523cbe50490613dbb68b2a4d35cfa704efc2fd2/docs/DEPENDENCY_REFRESH_2026_11.md)
- [Storage configuration](https://github.com/Vantiger-Construction/neura_os/blob/6523cbe50490613dbb68b2a4d35cfa704efc2fd2/lib/services/neura_secure_storage.dart)
- [Microsoft SAPI recognizers](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms718548(v=vs.85))
- [Android adb](https://developer.android.com/tools/adb), [logcat](https://developer.android.com/tools/logcat), [apksigner](https://developer.android.com/tools/apksigner), [apkanalyzer](https://developer.android.com/tools/apkanalyzer)
- [Android on-device recognizer](https://developer.android.com/reference/android/speech/SpeechRecognizer#createOnDeviceSpeechRecognizer(android.content.Context))

From the repository root, helper regressions need only Python:

```powershell
python -m unittest discover -s tools/startup_voice_diagnostics -p 'test_*.py' -v
```

The existing application regressions require the branch's Flutter 3.47.9 / Dart
3.13.7 toolchain, with locked dependencies; do not substitute an older SDK:

```powershell
flutter pub get --enforce-lockfile
flutter test --no-pub --concurrency 2 --timeout 2m test/startup/neura_startup_voice_test.dart test/services/neura_local_speech_input_test.dart test/services/neura_startup_voice_prefs_test.dart test/screens/neura_startup_voice_settings_test.dart test/data_wipe_microphone_test.dart test/services/neura_cloud_transaction_test.dart test/services/neura_model_router_test.dart
```

These synthetic tests do not open real microphones or prove hardware acceptance.
They were not rerun in the Linux kit-building environment without Flutter. See
`AUTOMATED_RESULTS.md` for the checks actually performed and their scope.

