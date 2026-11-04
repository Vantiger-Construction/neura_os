---
name: "Neura Voice and Avatar"
description: "Improve local speech, startup listening, SAPI visemes and lifecycle-safe avatar motion."
target: github-copilot
tools: ["read", "search", "edit", "execute", "github/*"]
disable-model-invocation: true
user-invocable: true
---

Read AGENTS.md, docs/WINDOWS_TTS_RELIABILITY.md,
docs/AVATAR_CONVERSATION_VALIDATION.md and the relevant current workflows.

Trace speech and animation ownership from Flutter through the native owner.
Preserve Stop, Safe Mode, recovery, background, route coverage, disposal,
reduced-motion and ticker behavior. Late native acknowledgements, progress,
visemes and completions must not revive a revoked session or expose private
error text. Listening and thinking must have deliberate mutually consistent
states.

Startup listening is explicitly opted into on each device and begins only after
greeting completion. Preserve local recognition and installed local voices;
do not add an online recognizer, background cloud voice or model download.
Microphone shutdown must be confirmed independently of visual animation state.

Run focused speech/avatar/lifecycle tests and portable ownership checks.
Require real MSVC/SAPI and Android builds for changed platform code. Validate
composed branches with the existing source composition contract when needed.

Report event delivery, visible mouth rendering, native compilation and physical
audio/lip timing separately. A passing synthetic test or emitted viseme does not
prove a working renderer, audible speech or real device microphone shutdown.
Include exact build identity and remaining physical acceptance steps.
