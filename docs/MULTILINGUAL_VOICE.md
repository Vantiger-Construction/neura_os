# Multilingual voice and note-taking

Neura listens, understands and replies in **English, Spanish, Italian, German
and French**, and can write down what people say in any of them. Everything
stays on the device.

## How it works

| Step | What happens |
| --- | --- |
| Listening | The recognizer is asked for the chosen listening language, or detects it (Automatic). |
| Understanding | The language each turn was in comes from the recognizer, or a clear guess from the words. |
| Replying | The offline model gets a one-line per-turn note ("They are speaking Spanish. Reply only in Spanish…"). English adds nothing. |
| Speaking | Her voice switches to an installed local voice for that language, then back. With no such voice the reply is shown, not read in the wrong voice. |

Hands-free conversation ("Talk freely") works the same in every language:
after each spoken reply she listens again until you say "Neura, stop", tap the
mic or leave chat.

## Recognizers

| Platform | Recognizer | Languages |
| --- | --- | --- |
| Windows, offline model (recommended) | Sherpa-ONNX Whisper + Silero VAD, profile `whisper-base-int8` or `whisper-small-int8` | All five, detected per phrase |
| Windows, built-in | Microsoft desktop (SAPI) dictation | Each installed language pack; Italian is not offered by Windows desktop dictation |
| Android 12+ | On-device `SpeechRecognizer` | Each downloaded on-device language pack |

Set up the offline multilingual model (explicit, person-run, license-gated):

```powershell
.\tools\Install-NeuraOfflineSpeech.ps1 -Model MultilingualBase `
  -AcceptModelLicense -SetEnvironment -VcpkgRoot C:\vcpkg -Build
```

Use `-Model MultilingualSmall` for better accuracy at about three times the
size and decode time. Measure on the 8 GB target before making it the default.

Choose **Settings → Neura's Voice → Languages → Listening language**:
*Automatic* (detect, recommended with the offline model) or one language
(required for SAPI and Android to listen in a language other than their
default). A chosen language never falls back to another one; Neura says which
recognizer or language pack is missing instead.

For spoken replies, install a voice per language in the system speech
settings (Windows: *Time & language → Speech*; Android: *Text-to-speech*,
downloaded voices only). The Languages section lists what is installed.

## Notes

| Say | Does |
| --- | --- |
| "Neura, take a note: …" · "toma nota …" · "prendi nota …" · "notiere …" · "prends note …" | Saves what follows as one note |
| "Neura, start taking notes" · "empieza a tomar notas" · "prendi appunti" · "schreib mit" · "prends des notes" | After an on-screen confirmation that everyone nearby knows, writes down everything heard, without replying |
| "Neura, stop taking notes" (or tap the mic) | Saves the notes |
| "Neura, open my notes" | Opens the notes list |

Typed requests work too ("take a note: …"). Notes are encrypted with the
device key, kept only on this device, separate from the journal, never copied
into companion memory or a model prompt, and erased by a data wipe. Leaving
chat, the background or Safe Mode pause note-taking; unsaved words stay on
screen until you save or discard them. Crisis language is never filed away as
a note; it always gets the normal reply.

## Validation status

Synthetic Dart, C++ pipeline and Python checks cover parsing, language
detection, the bounded VAD/Whisper decode pipeline, Safe Mode discard and
wipe. Physical acceptance on Windows (each recognizer, each language, voice
switching) and Android (language packs) has **not** been run.
