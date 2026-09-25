# Neura Living Companion Upgrades

This slice makes Neura feel present throughout the app while preserving the
existing authority boundaries. It does not add background cloud calls,
background microphone access, implicit memory, or automatic side effects.

## 1. Room presence foundation

Every built-in room has a content-free presence profile: a stance, a short
room cue, a safe avatar alignment, and local activity IDs. The main shell now
renders Neura inside her dedicated stage using the selected avatar. Room
changes cross-fade/slide the stage without covering workspace controls.

## 2. Faster conversational voice

Streamed speech can start at a long, completed clause instead of waiting for
unusually long sentences. Sentence boundaries still win; cancellation and
barge-in discard every unsaid chunk.

## 3. Consent-aware context receipts

Every visible bot reply carries an in-memory **Context used** receipt. It shows
only categories such as visible history, selected text, permitted memory,
image, room, route, and whether the reply may be remembered. It never stores
the prompt, filename, memory content, journal text, or credentials.

## 4. Room activities

Room profiles map to existing safe navigation commands. When enabled, Neura's
stage suggests relevant local activities, such as journaling in Reflection Bay
or a mood check-in in the Mood Den. A shortcut only opens the existing surface;
it does not complete, save, or approve anything.

## 5. Safe multi-step actions

`NeuraActionPlan` sequences already-reviewed Action Loom actions. It exposes
one step at a time, cannot approve or execute, advances only after that exact
step reports `executed`, and blocks rather than skipping a denied, expired,
blocked, or failed step. Each side effect keeps its own fresh approval.

## 6. Offline intelligence

The deterministic on-device fallback is now room-aware and returns structured
intent plus optional small steps. It reads no saved memory, uses no network,
and executes nothing. Image requests clearly say pixels cannot be inspected
offline. Urgent-safety language points to immediate human help and the Support
Center.

## 7. Windows–Android handoff visibility

The existing signed, encrypted continuity kernel now exposes a metadata-only
health snapshot: active/revoked counts, relay count, allowed categories, and
handoff readiness. No device name, fingerprint, pairing code, or payload is
included. Private-record relay policy remains fail-closed.

## 8. Avatar runtime bridge

`NeuraAvatarRuntimeBridge` publishes a versioned presentation contract for
Rive, the Windows mascot, Unity, or a future renderer. The contract contains
only room ID, presence phase, stance, motion, scale, and Safe Mode. It carries
no user content and grants no microphone, cloud, memory, or action authority.

## 9. Companion customization

Settings now includes Still/Subtle/Expressive motion, Compact/Standard/Large
stage size, and room-activity hints. Preferences remain local. Safe Mode and
the accessibility safety switch force companion motion to Still.

## 10. Self-health dashboard

Diagnostics now includes an expandable Companion health card for safety,
voice, intelligence route, memory receipts, action plans, continuity, and the
avatar bridge. It is deliberately content-free and cannot export private data.

## Required device QA

- Windows: TTS first-phrase latency, barge-in, native microphone permissions,
  Safe Mode during recognition, Rive/Lottie fallback, and mascot visibility.
- Android: room transitions, compact stage layout, activity shortcuts, and
  signed handoff pairing/apply on two physical devices.
- Optional Unity host: deserialize contract `v: 1`, reject unknown versions,
  and verify that Safe Mode always produces `motion: still`.
