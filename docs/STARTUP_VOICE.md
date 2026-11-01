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

Local validation with Flutter 3.47.5 / Dart 3.13.4 on Linux:

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

Primary API references:

- [Microsoft SAPI recognizers](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms718548(v=vs.85))
- [SAPI dictation activation and microphone setup](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms718917(v=vs.85))
- [Android on-device SpeechRecognizer](https://developer.android.com/reference/android/speech/SpeechRecognizer#createOnDeviceSpeechRecognizer(android.content.Context))
- [Windows online topic-constraint recognition](https://learn.microsoft.com/en-us/windows/apps/develop/input/speech-recognition)
