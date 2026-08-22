# Neura Adaptive Intent OS — v1.4 research prototype

This branch introduces a local-only prototype for a new Neura computing layer:

1. **Cognitive Bandwidth Engine** — estimates practical available attention from explicit, privacy-safe signals. It is not a medical diagnostic system.
2. **Adaptive Interface Policy** — changes visible action count, information density, proactive behavior, and consent strictness.
3. **Intent-to-Outcome Compiler** — turns a requested outcome into a reversible action graph.
4. **Personal Constitution** — enforces local/cloud, communication, purchase, calendar, work-hour, and sensitive-content boundaries.
5. **Decision Receipts** — explain the selected mode, policy blocks, approvals, confidence, and why each plan was produced.

## Safety boundary

The v1.4 prototype is proposal-only. It does not:

- send messages;
- modify calendars;
- purchase anything;
- call cloud AI;
- execute Action Loom operations.

A later phase can hand approved steps to Action Loom using exact payload binding and fresh authorization. This prototype establishes the deterministic policy and explanation layer first.

## Local demo

Open **Adaptive Intent** from the Neura dashboard. Adjust the local capacity signals, review the resulting mode, choose constitution boundaries, and compile an outcome.

## Validation

Targeted tests cover:

- Recovery, Simplified, Balanced, and Deep Focus state selection;
- Safe Mode overrides;
- interface policy mapping;
- cloud, message, purchase, calendar, sensitive-content, and work-hour boundaries;
- adaptive plan compilation and decision receipts;
- controller invalidation when signals or Safe Mode change.
