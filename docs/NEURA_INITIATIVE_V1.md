# Neura Initiative v1

Routine-aware initiative and room-aware attention for Neura's existing
proactive intelligence pipeline. This is the `neura-initiative` design ported
onto the real code: most of that design (interrupt cost, privacy gating,
learning from accept/dismiss, wellness nudges) already existed in the
Autonomy Kernel, Opportunity Radar, and specialist reputation, so v1 adds only
the two pieces that were missing.

## What it adds

**Room attention** (`lib/intelligence/room_attention_policy.dart`)

The Autonomy Kernel now knows which `NeuraRoom` the user is in
(`NeuraAutonomyPolicy.roomId`). The check is tightening-only, like the Personal
Constitution: it can suppress a candidate, never allow one.

| Room | Attention | Effect on non-urgent candidates (urgency < 0.85) |
|---|---|---|
| `reflection_bay` | private | suppressed |
| `legacy_vault` | private | suppressed |
| `mood_den` | calm | suppressed if disruption > 0.35 |
| all others | open | no change |

Edit the table in `NeuraRoomAttentionPolicy._byRoomId` to change which rooms
are private or calm.

**Routine initiative** (`lib/intelligence/routine_model.dart`,
`lib/intelligence/initiative_source.dart`)

A content-free hour-of-week histogram of app opens feeds two new specialists:

- `initiative.arrival` — "Welcome back" after 3+ days away. Shown as the new
  `ProactiveBannerKind.presence` card.
- `initiative.routine_shift` — a gentle check-in when Neura is opened between
  midnight and 5am at an hour the user almost never visits (needs 14+ active
  days and 30+ opens of history). Shown as a wellness card.

Both are ordinary `NeuraIntelligenceCandidate`s, so they go through the full
kernel (Safe Mode, quiet hours, focus, room, caps, consent, constitution) and
app guardrails, and their specialist reputation learns from accept/dismiss
like every other specialist.

## Privacy

- Stored: hour-of-week counts, up to 60 active day keys, last-seen time,
  timezone name/offset, and at most one pending return's timestamps. No
  content, screens, or conversation data.
- Routine history is read for inference and recorded only when proactive
  suggestions and `allowLearning` are on and Safe Mode is off. Disabling any
  of these gates clears the in-memory baseline and queues removal of the
  stored routine. Re-enabling starts a fresh baseline.
- Key `neura.initiative.routine.v1` lives in the prefs store the data wipe
  clears; its JSON schema is now v2. Old v1 history has no timezone provenance
  and is discarded. Travel or a DST offset change resets local-hour history;
  a clock rollback produces no initiative until time catches up.
- Routine recording updates memory synchronously and persists through the
  banner service's queue without holding up banner evaluation. Concurrent
  callers have one evaluation owner; offered initiative cards are reserved
  until shown, released by an unmounted card, or expired.
- Quiet hours, cooldowns and room suppression preserve a pending welcome.
  Only the rendered-frame acknowledgement consumes it. A presence greeting
  has no Open button or navigation outcome; Not now remains available.
- Submitted platform writes cannot be cancelled. If the banner queue misses
  the wipe drain deadline, preference deletion is deferred, the wipe reports
  incomplete, and producers stay suspended in Safe Mode. A retry must drain
  the original queue before clearing preferences. There is no detached
  post-wipe cleanup that could delete a fresh routine.

See [PR #148 validation](PR148_VALIDATION.md) for review reproductions,
dependency provenance, commands and the limits of local validation.

## Not ported

The original design's nightly "dream" policy digest is not included:
specialist reputation already decays toward neutral on every outcome, which
covers the same need without a background job.
