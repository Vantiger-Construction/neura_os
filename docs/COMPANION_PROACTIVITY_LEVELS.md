# Companion proactivity levels

Neura's dashboard suggestions now expose an explicit three-position control:

- **Off** — no unsolicited companion suggestions.
- **Subtle** — at most one quiet, dismissible card per day.
- **Balanced** — context-sensitive cards under the existing daily, hourly,
  cognitive-load, focus, and guardrail limits.

The existing personal daily cap remains available. A level can only tighten
that cap: Subtle limits it to one and Off to zero. Three consecutive
dismissals still expand the cooldown to seven days.

Suggestions remain non-directive and local. The dashboard card is not an
accessibility live region, never auto-speaks, always offers **Not now**, and
requires the existing review flow for approval-gated capabilities. Safe Mode,
quiet hours, pauses, Focus modes, high cognitive load, outcome-loop
suppression, distress guardrails, sensitive-signal policy, and the Personal
Constitution continue to suppress or block candidates before presentation.

Legacy saved state migrates conservatively: an old disabled switch becomes
the explicit Off level; an old enabled state becomes Balanced so existing
behavior does not silently grow more proactive.

