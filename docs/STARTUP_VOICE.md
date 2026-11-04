# Voice on startup

Enable **Settings → Neura's Voice → Voice on startup** once on each device.
The setting requires microphone permission and an available on-device speech
engine and voice. **Start voice now** opens the same experience immediately.
Enabling it selects **After reply** if automatic reply speech was previously
off; an existing After reply/As it arrives choice is preserved.

After normal startup and any sign-in/device-lock screen, Neura opens voice
chat once per process. She says, “Hi, I'm Neura. I'm here and ready to listen,”
then starts the microphone only after speech completion. The existing chat
controls show listening state, stop the conversation, mute replies and handle
local voice commands. Recognized chat messages use the existing model-routing
and per-request cloud approval interface. This setting does not start a model
download or authorize a cloud request.

The microphone stops when the app loses focus, is backgrounded, the voice
route is covered/closed, the startup setting is disabled, Safe Mode is entered,
restart-required recovery is signalled, or full data removal begins. Returning
to the foreground does not silently restart the conversation. Tap the chat mic
or Start voice now when ready. Native Windows focus/minimize/suspend/close
handling and Android Activity.onPause also stop the recognizer independently
of Dart delivery.

## Platform support

| Platform | Startup input | Startup output |
| --- | --- | --- |
| Windows | Owned in-process SAPI recognizer, restricted to installed Microsoft `MS-…-DESK` tokens; no WinRT online dictation or third-party/default engine fallback. | Existing owned Microsoft desktop SAPI voices. |
| Android 12/API 31+ | `isOnDeviceRecognitionAvailable` followed exclusively by `createOnDeviceSpeechRecognizer`; permission and foreground checks; no default recognizer fallback. | An installed voice reporting `network_required=0`, excluding `notInstalled` voices. |
| Older Android, other platforms, missing language packs/engines | Automatic startup voice is unavailable. Text chat remains available. | No implicit online voice fallback. |

This is foreground voice chat, independent of ambient clip recording and the
existing Hey Neura preference. It does not enable either of those features.
It pauses their active sessions before the greeting to avoid competing for the
microphone. The existing manually opened chat/Voice Journal platform input
paths are separate; this change does not label those legacy paths local-only.

Startup input keeps a bounded current phrase in RAM, sends it only into the
visible chat flow, and clears its buffers on Stop. Native polling is identified
by a revocable session number, so stale start acknowledgements/poll results
cannot restore listening or insert text after cancellation. No raw-audio
recording, background speech processing, transcript logging or memory permission
is enabled by this feature. A wipe suspends the saved setting and waits for its
submitted preference writes before clearing preferences; an unconfirmed native
shutdown or writer drain fails the wipe rather than claiming success.

## Validation and acceptance

Synthetic tests cover greeting-before-microphone ordering, permission denial,
missing local engines, stale starts/polls, background/Stop/disposal, saved
opt-in/out, local output voice selection and preference-writer draining. The
Windows local speech workflow compiles the actual SAPI owner along with the
TTS owner and builds the Windows application. Unit tests do not activate a
real microphone or speaker.

Historical validation before the dependency integration, with Flutter 3.47.5 /
Dart 3.13.4 on Linux (these results do not validate the current PR head):

- 959/959 Flutter tests passed with coverage (`--no-pub --concurrency 4 --coverage`).
- Full strict analysis found no issues; canonical formatting and diff checks passed.
- Three regenerated Windows-plugin exclusion tests passed.
- CMake built the portable ownership harness and its 17 assertions passed;
  this Linux harness does not compile or execute the Windows SAPI owner.
- Dependency lockfiles and existing workflow action pins are unchanged.

Windows/Android native builds and physical acceptance must be verified on the
new head. In particular, installed Windows language-pack compatibility and
Samsung Android 16 on-device recognition/permission/silence behavior remain
device checks. A successful mocked test is not proof of audible speech,
recognition quality or a successful APK installation.

### November 4 integration repair

PR #161 incorporates PR #170's original `8e661cce` file-picker migration commit
without rewriting its six files. That fixes the inherited compile errors from
the #150/#162 integration. The conversation and visible-mouth jobs use reviewed
SAPI head `25369433` and Flutter 3.47.9. Startup chat releases its status-stream
subscription and startup-consent listener on disposal.
The disposable composer keeps the source PR's conversation, Windows speech and
visible-mouth workflow definitions when their older dependency copies conflict;
application, test and lockfile conflicts still fail. Regression fixtures cover
the visible-mouth exception and rejection of conflicting speech application code.

Startup greeting speech now requires an actual completion callback. Rejected,
cancelled or disabled speech must leave the microphone off and return to text
chat. Three regression tests reproduced premature microphone starts for those
cases before the repair; ordinary reply cancellation keeps its existing behavior.

The Windows speech lane explicitly runs the startup, input, preference and
settings regressions before compiling the real native owner and application.
`Android startup voice safety` runs synthetic regressions and builds the real
Android debug APK on an ephemeral hosted runner without production secrets.
Its artifact records the source commit/tree and APK SHA-256. This is separate
from the self-hosted packaging lane, whose November 4 failures occurred before
checkout because its system volume had less than the required 16 GiB free.
The packaging lane's existing space and delivery checks remain in force.

### Physical acceptance still required

Use a package built from the reviewed commit and verify its checksum first.
Use synthetic spoken phrases; do not upload private audio or transcripts.

| Check | Windows laptop | Samsung SM-S366V, Android 16 |
| --- | --- | --- |
| Installation and cold launch | Install/run the matching Windows build; confirm the dashboard and voice route load without a SAPI crash. | Install the matching debug APK and verify its application ID/version; confirm the previous blank-screen/launch failure is absent. |
| Explicit consent | With startup voice off, cold launch is silent and does not capture; enable it through Settings and relaunch. | Start with a fresh or revoked microphone grant; denial must leave text chat available and capture off. Enable startup voice only after permission and engine checks pass. |
| Greeting then input | Hear one complete greeting; the input indicator must remain off until the greeting finishes. Speak a synthetic phrase and verify one matching visible chat submission. | Repeat with an installed offline TTS voice and the on-device recognizer. Check greeting ordering and one recognized submission after relaunch. |
| Local operation | Disable networking and repeat using installed Microsoft desktop speech language packs. No cloud approval, model download or online dictation is required for input/output. | Repeat in airplane mode with installed language support; unavailable local recognition or voices must fail closed without an online fallback or download. |
| Shutdown and late events | During both greeting and listening, exercise Stop, mute/interruption, focus loss, minimize, route cover/close, opt-out, Safe Mode, restart-required recovery and wipe. Confirm OS microphone activity ends and late words do not enter chat. | Repeat with Home, lock screen, task switching, route cover/close, Stop, opt-out, permission revocation, Safe Mode and wipe. Confirm Android's microphone indicator and active recording clients clear. |
| Resume and silence | Return to the app after interruption; capture must stay off until an explicit gesture. Test silence/end-of-stream and missing local language packs. | Return from background and permission dialogs without a silent restart. Test silence, recognition errors and unavailable on-device services. |
| Cloud boundary | A recognized message requiring a cloud model must still show the exact-request approval. Cancel it and verify nothing is sent. | Repeat the approval/cancellation check; startup consent must not authorize cloud requests or saved-memory access. |

Record package identity, device/OS, installed local engine and voice, each
pass/fail result and any crash diagnostics. A hosted build, synthetic test or
independent code review does not satisfy these hardware checks.

Primary API references:

- [Microsoft SAPI recognizers](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms718548(v=vs.85))
- [SAPI dictation activation and microphone setup](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms718917(v=vs.85))
- [Android on-device SpeechRecognizer](https://developer.android.com/reference/android/speech/SpeechRecognizer#createOnDeviceSpeechRecognizer(android.content.Context))
- [Windows online topic-constraint recognition](https://learn.microsoft.com/en-us/windows/apps/develop/input/speech-recognition)
