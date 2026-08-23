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
   dependency-safe, explainable action graph.
4. **Personal Constitution** — enforces local/cloud, communication, purchase,
   calendar, work-hour, preview, and sensitive-content boundaries.
5. **Decision Receipts** — explain the selected mode, policy blocks, approvals,
   confidence, and why each plan was produced.
6. **Persistent local runtime** — shares one Safe Mode-aware controller across
   the dashboard and Adaptive Intent screen.

## Phase 2 integration

- Capacity signals and constitution settings are persisted locally through
  Neura's cached SharedPreferences service.
- Signal readings expire after 12 hours so yesterday's low-energy or
  high-pressure state does not silently control a new day.
- Constitution choices remain until the user changes or resets them.
- Raw goals, compiled plans, action text, and decision graphs are never written
  to the Adaptive Intent settings store.
- Safe Mode changes immediately invalidate the current plan and force Recovery
  policy across every screen using the shared controller.
- The main dashboard now always shows an Adaptive Intent status card. It remains
  visible even when no proactive Intelligence Fabric suggestion is available.
- Initialization failures are retryable and do not poison the controller for
  the rest of the process.
- Rapid slider changes use a bounded persistence debounce rather than writing
  every intermediate value.

## Safety boundary

The v1.4 prototype remains proposal-only. It does not:

- send messages;
- modify calendars;
- purchase anything;
- call cloud AI;
- execute Action Loom operations.

A later phase can translate an explicitly selected, policy-allowed local step
into an Action Loom proposal with exact payload binding and fresh authorization.
Unknown, blocked, critical, or external steps must continue to fail closed.

## Local demo

Open Neura's dashboard and select the **Adaptive Intent** status card. Adjust
the local capacity signals, review the resulting mode, choose constitution
boundaries and work hours, and compile an outcome.

## Validation

Focused tests cover:

- Recovery, Simplified, Balanced, and Deep Focus state selection;
- Safe Mode overrides and live Safe Mode binding;
- interface policy mapping;
- cloud, message, purchase, calendar, sensitive-content, preview, and work-hour
  boundaries;
- adaptive plan compilation and decision receipts;
- controller invalidation when signals or Safe Mode change;
- fresh-state restore and stale-signal expiry;
- retry after a transient local-store initialization failure;
- proof that compiled goal text is not persisted.

The PR validation workflow requires canonical formatting, zero analyzer
findings, the focused Adaptive Intent suite, and Neura's complete Flutter test
suite before this research branch can be considered ready for review.
