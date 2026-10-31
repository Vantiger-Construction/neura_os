# Avatar conversation validation

PR #157 owns listening/thinking and chat-turn cancellation. PR #158 owns
Windows SAPI viseme delivery and synchronous speech-animation revocation.
PR #149 owns the shared body and the separate mascot's motion lifecycle.
Keep these changes independently reviewable. The integration workflow merges
exact reviewed commits only inside its disposable checkout; it never pushes
the combined source or changes a PR's base.

## Automated checks

`test/modules/chat/neura_conversation_presence_test.dart` uses the real chat
screen, conversation signal, AI orchestration, owned Windows speech adapter,
avatar orchestrator, and numeric viseme wiring. Synthetic native channels
replace microphone capture, Ollama inference, Rust transport, and SAPI audio.
Injected AI/speech services are borrowed; their test owner disposes them.
Filesystem logging is suspended in this isolated test process. This suite
does not test log durability, real models, voice quality, or device playback.

It covers listening, first answer, thinking, speaking, completion, explicit
interruption, model cancellation, Safe Mode, disposal, background/foreground,
late native polls, route coverage, and approval dialogs. The Rust adapter's
typed-text grant must never start the microphone, SAPI, or Ollama. An opaque
route ends chat activity; an approval dialog remains part of its active turn.
Presentation events carry only booleans, bounded mouth openness, and viseme
enums. Windows ignores the legacy plugin channel and text-progress guesses.

Run the independent #157 tests without feature composition:

```sh
flutter pub get --enforce-lockfile
flutter test --no-pub test/modules/chat test/avatar/conversation_presence_signal_test.dart
```

On the exact combined source, require native visemes as well:

```sh
flutter test --no-pub --dart-define=NEURA_VALIDATE_NATIVE_VISEMES=true test/modules/chat/neura_conversation_presence_test.dart test/services/neura_native_viseme_lifecycle_test.dart
flutter test --no-pub --dart-define=NEURA_VALIDATE_NATIVE_VISEMES=true
```

The definition enables additional controller-level native-viseme assertions;
it does not select a model, enable a microphone, or change production policy.
The composition workflow also runs #149's body, room, route, and mascot
regressions. On Windows it compiles the genuine SAPI owner, runs the native
ownership/escaping tests without audio, and builds the production application
while checking that the legacy `flutter_tts_plugin.dll` is absent.

All integration pins must still equal their source branch heads. A changed
dependency fails the workflow and requires a reviewed pin refresh. Before
merging, recheck the PR head, checks, review decisions, unresolved threads,
and applicable branch/ruleset protections. A clean local merge or green test
run is not an independent approval. Do not bypass protections or enable
auto-merge while acceptance or review blockers remain.

## Rendering limitation

These changes deliver native mouth-shape events into the avatar controller.
They do **not** establish that the selected artwork visibly moves its lips:

- `lib/avatar/renderers/rive_avatar_view.dart` is a fallback stub.
- The default `neura_fullbody.png` rendering is a static image wrapped in
  procedural body transforms. It does not deform a mouth.
- The mascot also renders that image. Its `mouth` event drives body motion,
  not an independently animated lip rig.

A functioning mouth renderer and compatible rig/artwork are required before
claiming visible lip synchronization. This is an implementation prerequisite,
separate from whether SAPI viseme polling or numeric controller wiring passes.
Do not mark a static-image or stub-renderer observation as a lip-sync PASS.

## Physical Windows acceptance: still required

Use a separate clean checkout and synthetic profile on the actual Windows PC.
Record the exact combined source commits/tree, executable and DLL SHA-256s,
build mode, Windows version, installed Microsoft desktop voice, output device,
and available RAM. Preserve the old bundle and matching PDBs. A binary from
only one PR is not the combined implementation. Do not infer APK or PC
acceptance from these synthetic tests.

Prepare the build and any already approved local model before testing offline.
Preserve model preflight memory limits; never auto-download a model or enable
cloud fallback. The Rust adapter remains text-only and consent gated. Keep
ambient/wake-word capture and startup greeting disabled. Enable chat capture
and reply speech explicitly only for the supervised scenarios below.

First follow [the existing speech inspection and observation helper](../tools/windows_speech_validation/README.md)
and [Windows speech reliability procedure](WINDOWS_TTS_RELIABILITY.md).
`Inspect.cmd` checks an existing bundle without launching it; `Observe.cmd`
records the operator's actual observations. Neither proves a successful
playback without observation. Source fingerprint comparison is only meaningful
against a manifest for the exact combined source: #149 modifies speech files,
so do not reuse #158-only source hashes to attest the integration build.

| Scenario | Physical evidence and pass condition |
| --- | --- |
| Mouth renderer prerequisite | Identify a working renderer/rig with native viseme inputs. If only the current image/stub is present, record visible lip sync as BLOCKED. Body motion may be tested separately. |
| Listening and thinking | Explicitly start chat capture, speak synthetic text, and finish the phrase. The avatar listens during capture, then thinks while the local reply is pending. Neither phase remains active when native speech starts. |
| Native speech | With a compatible mouth renderer, observe 10 short synthetic replies and one longer reply. Mouth shapes vary with actual audio, bilabials close, and silence/completion returns to rest. Record noticeable timing mismatch; a constant open mouth or text-estimate-only motion fails. |
| First reply | Repeat with an uncached first request after a cold launch and with a warm model. No premature speech, simultaneous listening/talking, or cloud request is permitted. |
| Interruption | During generation, press Stop. During audible speech, use Interrupt and talk, then send a fresh turn. Repeat 10 cycles. Old audio and mouth events never resume or terminate the replacement; microphone return must follow native shutdown. |
| Cancellation | Cancel before the first answer and while a spoken phrase is playing. No late reply or stale speech animation appears. |
| Safe Mode | Enter Safe Mode during capture, thinking, and speech. Repeat 10 speech cycles. Capture/audio stop, mouth rests, and returning to normal mode does not resume the old turn. New activity requires explicit action. |
| Background and recovery | Minimize or background during capture, generation, and speech; restore. Repeat 10 speech cycles. The main body and mascot freeze while inactive, no audio/capture resumes automatically, and a fresh explicit turn works. |
| Routes and accessibility | Cover chat with another page, then return; test Still/reduced motion. Covered or disabled bodies stop sampling. Approval dialogs remain usable. Closing a voice preview must not revive its audio or animation. |
| Mascot | Test the separate window with main-window focus/minimize/restore, Safe Mode, shutdown and settings changes. It must obey explicit main-window activity even though its own lifecycle is managed separately. The current image supports body response, not a lip-sync PASS. |
| Local backends | Test installed Ollama within its memory preflight limits; test the explicitly enabled Rust adapter separately. Rust chat has thinking/text only and must not acquire microphone/speech or include files, journals, or persistent memories. |
| Resource use | Compare idle and repeated-turn process memory/CPU on the same build/profile. After stop/background, no speech polling or stale turn activity continues. Record observed values; synthetic tests provide no performance measurement for this PC. |

Record PASS/FAIL/BLOCKED/NOT RUN and completed repetitions per scenario, using
only synthetic text. On a crash, overlap, late audio, freeze, or restart-required
failure, stop the session and preserve the exact bundle and filtered evidence.
Keep recordings/dumps private unless explicitly reviewed for sharing. Issue
#32's physical Windows acceptance remains open until this work is observed.
