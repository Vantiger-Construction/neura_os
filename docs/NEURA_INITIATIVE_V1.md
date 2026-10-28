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

- Stored: hour-of-week counts, up to 60 active day keys, last-seen time. No
  content, screens, or conversation data.
- Recorded only when proactive suggestions are on **and** the user's
  `allowLearning` preference is on.
- Key `neura.initiative.routine.v1` lives in the prefs store the data wipe
  clears, and is written only through the banner service's generation-guarded
  write queue, so an in-flight wipe cannot resurrect it.

## Not ported

The original design's nightly "dream" policy digest is not included:
specialist reputation already decays toward neutral on every outcome, which
covers the same need without a background job.
