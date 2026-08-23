# Neura Adaptive Intent OS — v1.4 research prototype

This branch develops a local-first Neura computing layer that adapts interface
complexity, planning depth, and consent requirements to a practical estimate of
the user's available cognitive bandwidth. It is not a medical diagnostic
system.

## Current technology

1. **Cognitive Bandwidth Engine** — estimates Recovery, Simplified, Balanced,
   or Deep Focus mode from explicit, privacy-safe capacity signals.
2. **Adaptive Interface Policy** — controls visible action count, information
   density, proactive behavior, and minimum consent strength.
3. **Intent-to-Outcome Compiler** — converts a requested outcome into a
   bounded, explainable action graph.
4. **Personal Constitution** — enforces local/cloud, communication, purchase,
   calendar, work-hour, preview, and sensitive-content boundaries.
5. **Decision Receipts** — explain the selected mode, policy blocks, approvals,
   confidence, and why each plan was produced.
6. **Persistent local runtime** — shares one Safe Mode-aware controller across
   the dashboard and Adaptive Intent screen.
7. **Deterministic Plan Sessions** — track user-directed local progress through
   pending, completed, deferred, blocked, completed-session, and abandoned
   states.
8. **Adaptive Outcome Loop** — converts privacy-safe completion evidence into a
   conservative recommendation to reduce load, maintain the current policy, or
   protect a focused outcome.

## Plan-session safety boundary

A Plan Session is progress tracking, not an executor.

- Every progress change requires a direct user gesture.
- Approval-gated local steps require an explicit approval flag.
- Blocked steps cannot be changed.
- Deferred steps must be resumed before completion.
- External effects cannot be marked complete by the local session engine.
- Safe Mode blocks session creation and progress changes.
- Only one active session is allowed in the Adaptive Intent runtime.
- Closing a session produces a derived receipt without storing the requested
  outcome, step title, step description, message text, or other raw plan copy.

The runtime keeps outcome receipts in memory only. A local-data wipe clears the
active session, derived history, last adaptation, and compiled plan.

## Outcome adaptation

The Outcome Loop examines at most five recent derived receipts.

It recommends **Reduce Load** when completion is low, reported effort is high,
interruptions are excessive, or a session was abandoned. It recommends
**Protect Focus** only after two repeated high-completion, high-satisfaction,
manageable-effort sessions and adequate current bandwidth. Otherwise it keeps
the existing policy.

An adaptation is an explainable recommendation. It cannot execute an action,
change a calendar, contact another person, purchase anything, or call cloud AI.

## Persistent Phase 2 integration

- Capacity signals and constitution settings are persisted locally through
  Neura's cached SharedPreferences service.
- Signal readings expire after 12 hours so yesterday's low-energy or
  high-pressure state does not silently control a new day.
- Constitution choices remain until the user changes or resets them.
- Raw goals, compiled plans, action text, and decision graphs are never written
  to the Adaptive Intent settings store.
- Safe Mode changes immediately invalidate the current compiled plan and force
  Recovery policy across every screen using the shared controller.
- The dashboard always shows an Adaptive Intent status card.
- Initialization failures are retryable and do not poison the controller for
  the rest of the process.
- Rapid slider changes use a bounded persistence debounce rather than writing
  every intermediate value.

## External-action boundary

The v1.4 runtime still does not:

- send messages;
- modify calendars;
- purchase anything;
- call cloud AI;
- execute Action Loom operations.

A later phase can translate an explicitly selected, policy-allowed local step
into an Action Loom proposal with exact payload binding and fresh
authorization. Unknown, blocked, critical, or external steps must continue to
fail closed.

## Validation

The PR validation workflow requires:

- canonical Dart formatting;
- `flutter analyze --fatal-infos`;
- the complete Cognitive, Constitution, Intent Compiler, and Adaptive Intent
  test directories;
- Neura's complete Flutter test suite.

Focused coverage includes all bandwidth modes, Safe Mode overrides, persisted
state expiry, constitution boundaries, plan-session transitions, direct-gesture
and approval requirements, privacy-safe outcome receipts, overloaded-session
reduction, repeated-success focus protection, one-session runtime authority,
and data-wipe reset behavior.
