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

Users can also mark any room calm or private under **Room attention** in the
Intelligence Center (`NeuraIntelligencePreferences.roomAttention`). A choice
is merged with the table by `NeuraRoomAttentionPolicy.effectiveFor`, and the
stricter setting wins, so a user choice can tighten a room but can't loosen a
built-in calm or private one. Choices that are no stricter than the built-in
setting aren't stored. Loading ignores malformed entries and caps the map at 32
rooms with ids of 64 characters or fewer. The urgent override applies to
user-marked rooms too, and the suppression reason says the user marked the
room.

**Routine initiative** (`lib/intelligence/routine_model.dart`,
`lib/intelligence/initiative_source.dart`)

A content-free history of when Neura is opened feeds three specialists:

- `initiative.arrival` — "Welcome back" after 3+ days away. Shown as the new
  `ProactiveBannerKind.presence` card.
- `initiative.routine_shift` — a gentle check-in when Neura is opened between
  midnight and 5am at an hour the user almost never visits (needs 14+ active
  days and 30+ opens of history). Shown as a wellness card.
- `initiative.wind_down`: an evening offer (20:00 until midnight) after Neura
  was opened between midnight and 5am on 3 or more of the last 7 nights.
  Shown as a focus card that opens the Focus Office, where Wind Down is one
  tap away. The copy states only what Neura observed ("You've stopped by
  after midnight on 3 of the last 7 nights") and makes no claim about sleep
  or health. It's offered at most once a week; the cooldown starts when the
  card reaches a rendered frame and is saved with the routine, like the
  welcome-back acknowledgement. An active Wind Down or Deep Work focus mode
  suppresses it in the kernel, and dismissals lower it below the score bar
  quickly (it scores about 0.41 against a 0.38 bar).

All three are ordinary `NeuraIntelligenceCandidate`s, so they go through the full
kernel (Safe Mode, quiet hours, focus, room, caps, consent, constitution) and
app guardrails, and their specialist reputation learns from accept/dismiss
like every other specialist.

**Calibration**

Each initiative card that reaches a rendered frame is also recorded as a
display-only forecast. The outcome is whether the user accepts it before it
expires. See [SUGGESTION_CALIBRATION_INTEGRATION.md](SUGGESTION_CALIBRATION_INTEGRATION.md).

## Privacy

- Stored: hour-of-week counts, up to 60 active day keys, up to 14 late-night
  keys (the date of the evening a night with a visit after midnight began),
  the date a wind-down card was last shown, last-seen time, timezone
  name/offset, and at most one pending return's timestamps. No content,
  screens, or conversation data. The late-night and wind-down fields were
  added to schema v2 without a version bump: older builds ignore them and
  missing fields read as empty, so existing routine history is kept.
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
