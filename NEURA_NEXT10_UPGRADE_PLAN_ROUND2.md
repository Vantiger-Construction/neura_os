# Neura — Next 10 Upgrades, Round 2: Implementation Plan

Grounded against the tree as of 2026-09-14, after the first 10-upgrade round
(PR #80: signal-graph feedback loop, receipt explorer, crisis support,
trusted-contact sharing, dream/mood correlation, streaming TTS, sync-conflict
review, glanceable widget, scheduled backups — see
`NEURA_NEXT10_UPGRADE_PLAN.md` for that scope; nothing below duplicates it).

**The throughline this round:** Neura has grown several independent
"should Neura act/interrupt/allow this" engines that never compare notes —
`intelligence/` (Autonomy Kernel, Opportunity Radar, Signal Graph),
`cognitive/` + `adaptive_intent/` (Bandwidth Engine, Adaptive Outcome Loop),
and `constitution/` (Personal Constitution) each independently gate
attention or actions using their own state, their own thresholds, and their
own action representation. None of round 1's work touched this — it all
built *within* `intelligence/`. This round is mostly about wiring those
silos together, plus a few standalone gaps (notifications, Joy Engine,
recap) found the same way round 1 found dream/mood: two systems that
clearly should know about each other and don't.

**Update, post-merge audit (2026-09-14):** three PRs unrelated to either
round (#76 voice/companion presence, #77 approval-gated model router, #79
local-first Neura Care Loop) merged into `Neura` alongside round 1 and this
plan. A follow-up audit of the merged tree confirmed one more instance of
the throughline above (item 3 now cites it directly) and surfaced two
concrete, previously-unknown fragmentation issues in the `care/` surface
(folded into item 8, which grew from "two sources" to "three sources plus a
navigation split"). Nothing else in this document changed as a result —
items 1, 2, 4, 5, 6, 7, 9, 10 are unaffected by those three PRs.

---

## Phase 1 — Bridge the silos (foundational, no new UI)

### 1. Bandwidth Engine → Autonomy Policy

**Exists:** `cognitive/neura_bandwidth_engine.dart` computes `bandwidth`/
`strain`/`focus` and already gates its own suggestion tiers. `intelligence/
autonomy_kernel.dart`'s `NeuraAutonomyPolicy` has its own, unrelated
suppression inputs (`focusMode`, `safeMode`, `recentlyDeclined`, daily/hourly
caps) — the two never see the same picture.

**Missing:** any path from the Bandwidth Engine's score into the Autonomy
Kernel's suppression decision, or vice versa.

**Approach:**
- Add `NeuraAutonomyPolicy.bandwidthStrain` (0..1, default 0) alongside the
  existing suppression inputs.
- In `NeuraAutonomyKernel.evaluate`, treat high strain the same way
  `focusMode == deepWork` is already treated: raise the urgency bar
  (candidate.urgency < threshold → suppressed), not a hard block — mirrors
  the existing pattern exactly, no new suppression *kind*.
- `NeuraIntelligenceController.evaluateCandidates` reads
  `NeuraBandwidthEngine`'s current score when building the policy, same as
  it already reads `FocusController.instance.state.value`.

**Files:** `intelligence/autonomy_kernel.dart`, `intelligence/
neura_intelligence_controller.dart`, `cognitive/neura_bandwidth_engine.dart`
(read-only).

**Acceptance:** a synthetic high-strain state suppresses a candidate that
would otherwise pass, with a reason string naming bandwidth strain, exactly
the way deep-work suppression already reads today.

**Size:** S.

---

### 2. Adaptive Outcome Loop → Autonomy Policy

**Exists:** `adaptive_intent/neura_adaptive_outcome_loop.dart`'s
`NeuraAdaptiveOutcomeLoop.evaluate()` already produces a real recommendation
(`NeuraOutcomeAdaptation` with `suppressProactiveSuggestions`,
`recommendedMode`, `maxPrimaryActions`, `confidence`, `reasons`) from recent
Adaptive Intent session outcomes — abandoned sessions, low completion, high
effort. This is a second, independently-reasoned "should Neura back off"
signal that `NeuraAutonomyPolicy` never sees.

**Missing:** `NeuraOutcomeAdaptation.suppressProactiveSuggestions` has no
effect outside Adaptive Intent's own screens.

**Approach:**
- Same shape as item 1: add a boolean/urgency-threshold input to
  `NeuraAutonomyPolicy` derived from the loop's latest evaluation, computed
  from `NeuraEncryptedOutcomeStore.load()` (already exists, already bounded
  and encrypted) at the same point the policy is assembled.
- When `suppressProactiveSuggestions` is true, apply the same suppression
  path as bandwidth strain — do not invent a third distinct code path for
  what is functionally the same "hold back" decision.

**Files:** `intelligence/neura_intelligence_controller.dart`,
`adaptive_intent/neura_adaptive_outcome_loop.dart` (read-only),
`adaptive_intent/neura_outcome_store.dart` (read-only).

**Acceptance:** a synthetic outcome history that `NeuraAdaptiveOutcomeLoop`
already classifies as `reduceLoad` measurably suppresses Opportunity Radar
candidates in the same evaluation cycle.

**Size:** M — mainly in carefully not duplicating item 1's suppression
plumbing; do these two together so the shared code path is written once.

---

### 3. Reconcile Personal Constitution with the Autonomy/Capability boundary

**Exists:** `constitution/neura_personal_constitution.dart`'s
`NeuraPersonalConstitution.evaluate()` is a full, independent policy gate —
cloud AI, external messages, purchases, calendar writes, work-hours
restrictions — operating on `NeuraActionStep`/`NeuraActionEffect` from
`intent_compiler/neura_action_graph.dart`. `intelligence/
capability_registry.dart` gates the *same categories* (`exportPrivateData`,
`contactPerson`, `moveMoney`, `scheduleNotification`) via a completely
different action representation (`NeuraIntelligenceCandidate` +
capability id) and its own risk/approval model.

**Confirmed, not hypothetical — a fourth engine found in the post-merge
audit:** `services/neura_model_router.dart` (from PR #77, merged after this
plan was first drafted) defines its own `NeuraCloudApprovalHandler` /
`NeuraCloudApprovalDenied` to gate every Anthropic request with a
fresh-confirmation callback. It does not call
`intelligence/fresh_approval_lease.dart`'s `NeuraFreshApprovalLeaseRegistry`
(grepped directly — zero references) despite solving the same "bounded,
short-lived approval evidence" problem the lease registry already solves for
Action Loom. This is the clearest, most concrete instance of this item's
premise found so far — the audit step below should treat it as a fourth
system to reconcile, not just Constitution vs. Capability Registry.

**Missing:** nothing stops any of these three or four systems disagreeing —
an action a capability definition would allow could be one the Constitution
blocks, or vice versa, and the model router's cloud-approval callback has no
relationship to either. No single source of truth exists for "does this
action need fresh approval, and from what."

**Approach — audit first, this is not a blind merge:**
- Trace every real caller of `NeuraPersonalConstitution.evaluate()` and
  every real caller of `NeuraActionGraph`/`NeuraActionStep` to establish
  whether the Constitution path is actually reached today or is itself
  unused (the same kind of check that turned up the persona/audience
  wiring gap in item 7 — verify before assuming either way).
  Two adjacent findings are already useful either way: mark the path in
  `capability_registry.dart` that would need a Constitution check, or
  document that the Constitution *is* Neura's real policy source and
  `capability_registry.dart` needs to defer to it.
- Trace `neura_model_router.dart`'s `NeuraCloudApprovalHandler` call sites
  too (`services/neura_ai_service.dart` is the known caller per PR #77).
  Cloud-request approval is functionally the same "fresh, bounded consent"
  concept `fresh_approval_lease.dart` already implements — decide whether
  the model router should be migrated onto `NeuraFreshApprovalLeaseRegistry`
  instead of keeping its own parallel callback type, or whether there's a
  real reason (e.g. request-preview UI needs) it must stay separate. Do not
  silently merge them without confirming the UI contract
  (`neura_cloud_request_preview.dart`) still gets what it needs either way.
- Only after both traces, pick one direction: either (a) have
  `NeuraCapabilityRegistry.resolve()` consult
  `NeuraPersonalConstitution` for the categories that overlap
  (cloud/external/purchase/calendar), or (b) if the Constitution is truly
  dead code with no live caller, document that finding plainly rather than
  wiring dead code into a live path — and separately decide the model-router
  question above on its own merits, since it does not depend on how the
  Constitution question resolves.

**Files:** `constitution/neura_personal_constitution.dart`,
`intelligence/capability_registry.dart`, `intelligence/
fresh_approval_lease.dart`, `services/neura_model_router.dart`,
`widgets/neura_cloud_request_preview.dart` (read), `intent_compiler/
neura_action_graph.dart` (read to trace callers).

**Acceptance:** either a passing test demonstrating the Constitution and
the Capability Registry now agree on the same synthetic action, or a
written finding (in the PR description, not new code) that the
Constitution has no live caller and is out of scope for this round — plus,
separately, a written decision on the model-router question (migrate onto
`NeuraFreshApprovalLeaseRegistry`, or a documented reason it stays apart).

**Size:** M, mostly investigation, now covering four systems instead of
two (Constitution, Capability Registry, `fresh_approval_lease.dart`, model
router). **Do this one first in the phase** — its audit step may reveal
item 7's "dead code" framing was wrong, which is cheap to learn early and
expensive to learn after other work assumes it.

---

## Phase 2 — Standalone connections (each independent, parallelizable)

### 4. Promise due dates → notifications

**Exists:** `relationships/models/neura_promise.dart` has a real `dueAt`;
`relationships/services/promise_service.dart` tracks status transitions.
`notifications/neura_notifications_service.dart` currently only exposes
`scheduleDailyMoodNudge`-style calls — nothing schedules from a promise.

**Approach:** when `PromiseService` creates or updates a promise with a
non-null `dueAt`, call a new `NeuraNotificationsService` method
(`schedulePromiseReminder`, mirroring the existing scheduling pattern) and
cancel/reschedule it if the promise is completed or its due date changes.
Respect the existing notifications-enabled preference gate — do not add a
second, ungated notification path.

**Files:** `relationships/services/promise_service.dart`,
`notifications/neura_notifications_service.dart`,
`notifications/neura_notifications_prefs.dart` (read).

**Acceptance:** creating a promise with a due date schedules exactly one
reminder; completing or deleting it cancels that reminder; disabling
notifications globally suppresses it the same way existing reminders are
suppressed.

**Size:** S.

---

### 5. DistressDetector → Opportunity Radar / Care Mode

**Exists:** `relationships/services/distress_detector.dart` defines
`DistressSignal`/`DistressDetector` with real detection logic.
`dashboard/proactive_banner_service.dart` computes its own ad hoc
`distressScore` from the mood signal alone
(`((0.5 - mood) * 1.4).clamp(0.0, 0.7)`) for guardrail evaluation — it never
calls `DistressDetector` at all.

**Approach:**
- Replace (or blend with) the hand-rolled `distressScore` computation in
  `ProactiveBannerService.maybeGetBannerOnAppOpen` with
  `DistressDetector`'s real output, keeping the same bounded 0..1 contract
  the guardrail evaluation already expects.
- Consider whether `DistressDetector`'s signal should also feed the
  `care_support` specialist's severity threshold from round 1
  (`intelligence/opportunity_radar.dart`) as a second corroborating input,
  the same "two signals agree" pattern used for dream/mood — optional
  stretch within this item, not required for the core fix.

**Files:** `dashboard/proactive_banner_service.dart`,
`relationships/services/distress_detector.dart` (read),
`intelligence/opportunity_radar.dart` (only if doing the stretch goal).

**Acceptance:** `ProactiveBannerService`'s guardrail-facing distress score
now derives from `DistressDetector`'s real signal in a unit test with a
synthetic detector result, not only from raw mood arithmetic.

**Size:** S–M.

---

### 6. Quest-streak milestone → Joy Engine moment

**Exists:** `modules/quests/quest_store.dart` has a real `currentStreak()`.
`joy_engine/joy_engine.dart`'s `JoyEngine.pickMoment()` is currently invoked
only from mood, via `_joyCandidate` in `dashboard/proactive_banner_service.dart`.

**Approach:** add a `_streakJoyCandidate` alongside the existing
`_joyCandidate`/`_relationshipCandidate` methods in
`ProactiveBannerService`, firing on streak milestones (e.g. 7/14/30 days,
matching whatever round-number convention `currentStreak()` already
implies) with a `NeuraIntelligenceCandidate` using `openAppModule`, same
pattern as every other banner candidate — no new capability, no new banner
kind beyond reusing `.joy`.

**Files:** `dashboard/proactive_banner_service.dart`,
`modules/quests/quest_store.dart` (read).

**Acceptance:** reaching a milestone streak produces a joy candidate once
per milestone (not every day the streak holds), verified with a synthetic
streak sequence.

**Size:** S.

---

### 7. Audit and complete module-hint wiring in NeuraPromptBuilder

**Exists — corrects an initial assumption:** `persona/
audience_kids_safety_integration_notes.txt` and `integration_notes_persona_
mood_ai.txt` read like installation notes for unbuilt work, but they are
not: `services/neura_ai_service.dart` already calls
`NeuraPromptBuilder.instance.buildSystemMessage(...)` from the main chat
path (two call sites), and `kids/screens/kids_neura_chat_screen.dart` is a
real screen — not the `_stub_` screen the notes describe building. The
audience/safety system is live, not dead.

**Missing:** the notes describe passing a `module:` hint
(`'journal' | 'rituals' | 'care_mode' | 'dream_show' | 'weekly_snapshot' |
'kids_mode'`) so response style and safety profile differ per room, but the
main chat call site (`neura_ai_service.dart:157`) calls
`buildSystemMessage(agentId: agentId, includePersistentMemory: ...)` with
no visible `module` argument. Whether that's because the parameter is
optional-and-defaulted safely, or because per-module differentiation
silently never happens, needs to be confirmed by reading
`NeuraPromptBuilder.buildSystemMessage`'s full signature and every call
site, not assumed.

**Approach:**
- Read `persona/services/neura_prompt_builder.dart` in full and every call
  site of `buildSystemMessage`/`resolveStyle` to build the real picture.
- If module hints are missing where `NeuraChatPolicy.forRoom` already knows
  the room id (`services/neura_chat_policy.dart` — `mood_den`,
  `dream_atrium`, `legacy_vault`, etc. already exist as room identifiers),
  pass the corresponding module hint through at each call site — this is
  data already in scope at the call site, not new state.
- Treat `kids_mode`/child-audience wiring as the priority sub-item: confirm
  `NeuraAudience.child` is actually reachable end-to-end from
  `kids_neura_chat_screen.dart` through to the system prompt Neura's model
  actually receives, given this is the one sub-item with real safety
  stakes.

**Files:** `persona/services/neura_prompt_builder.dart`,
`persona/services/neura_audience_service.dart`, `services/neura_ai_service.dart`,
`services/neura_chat_policy.dart` (read), `kids/screens/kids_neura_chat_screen.dart`.

**Acceptance:** for each room id in `NeuraChatPolicy.knownRoomIds`, the
system prompt Neura's model receives differs in a way traceable to that
room (not identical text regardless of room); a test specifically confirms
the child-audience safety profile reaches the outgoing system prompt from
the kids chat screen's entry point.

**Size:** M — starts as investigation, per the corrected framing above;
scope the fix only after confirming what's actually missing.

---

## Phase 3 — Slower-burn, more design judgment

### 8. Consolidate the fragmented `care/` surface (text and navigation)

**Exists — grew from two sources to three, plus a navigation split, in the
post-merge audit:**
- `guardrails/support_resources.dart` is two hardcoded strings (988/911
  US-only).
- `care/services/crisis_playbook_service.dart` (round 1) is the richer,
  already-built system with real playbooks and region awareness potential.
- `care/services/neura_care_loop_service.dart` (new, from PR #79) defines
  its *own* `_immediateSupportPlan` with its own 988/emergency copy,
  triggered by `NeuraCareCheckIn.feelsUnsafe` — a third, independent
  crisis-text source nobody wrote with the other two in mind.
- Separately: `os_shell/screens/os_shell_home_screen.dart` links to
  `CareModeHomeScreen` (crisis playbooks, trusted contacts — round 1);
  `modules/navigation/enhanced_navigation.dart`'s dashboard tile grid links
  to `NeuraCareLoopScreen` (check-in → coping action — PR #79) instead. A
  user relying on one navigation surface has no path to the other feature.

**Approach:**
- Text: have `guardrails/guardrails_rules.dart` (or wherever
  `support_resources.dart` is actually consulted — trace this first, same
  discipline as item 7) and `NeuraCareLoopService._immediateSupportPlan`
  both reference `CrisisPlaybookService`/a shared resource list instead of
  each hardcoding their own pair, so a future update to crisis resources
  happens in one place, not three.
- Navigation: add a cross-link in each direction — a tile/entry point to
  Care Loop from `CareModeHomeScreen`, and one to Care Mode from
  `NeuraCareLoopScreen` (or its check-in result screen) — rather than
  merging the two features, since they serve genuinely different moments
  (an immediate coping action vs. browsing playbooks/contacts). Confirm
  with whoever owns product direction here before assuming cross-linking
  (not merging) is the right call; this plan documents the finding, not a
  final UX decision.

**Files:** `guardrails/support_resources.dart`,
`guardrails/guardrails_rules.dart`, `care/services/crisis_playbook_service.dart`,
`care/services/neura_care_loop_service.dart`,
`care/screens/care_mode_home_screen.dart`,
`care/screens/neura_care_loop_screen.dart`,
`os_shell/screens/os_shell_home_screen.dart`,
`modules/navigation/enhanced_navigation.dart`.

**Acceptance:** no behavior change for the guardrail path visible to users,
but only one source file defines the actual 988/911/emergency text, and
`NeuraCareLoopService` consumes it rather than duplicating it; from either
navigation surface, a user can reach both Care Mode and Care Loop within
one tap of wherever they currently land.

**Size:** M — grew from S once the third text source and the navigation
split were confirmed; the text consolidation and the navigation cross-link
are independent sub-tasks and can land separately.

---

### 9. Constitution-driven work-hours awareness in Focus/Quest suggestions

**Follow-on from item 3, only if that audit finds the Constitution live:**
`NeuraPersonalConstitution.workHoursStart/End` already exists and is
evaluated for external work actions. If item 3's audit finds real callers,
a natural, small follow-on is letting `focus_sprint`/`quest_micro_step`
Opportunity Radar candidates (round 1's existing specialists) respect the
same work-hours window for consistency, instead of Focus Mode being the
only attention boundary that matters.

**Files:** `intelligence/opportunity_radar.dart`,
`constitution/neura_personal_constitution.dart`.

**Acceptance:** deferred until item 3 resolves; do not start this item
before item 3's audit is written down.

**Size:** S, contingent.

---

### 10. Recurring dream/mood themes in the weekly/monthly recap

**Exists:** round 1 wired dream-mood valence into the Signal Graph for
*in-the-moment* correlation. `recap/services/neura_recap_service.dart` and
`insights/services/weekly_snapshot_export_service.dart` never look
backward at dream themes over the week/month, even though
`dreams/screens/dream_show2_screen.dart` already implies a "Monthly Dream
Show" concept and `DreamThemeService.computeSummary(days: ...)` already
supports an arbitrary window.

**Approach:** add a bounded (tag/mood-category only, matching round 1's
"never raw dream text" boundary) dream-theme summary section to whichever
of `neura_recap_service.dart`/`weekly_snapshot_export_service.dart` is the
actual user-facing weekly recap, reusing `DreamThemeService.computeSummary`
with a 7- or 30-day window rather than round 1's 14-day radar window.

**Files:** `recap/services/neura_recap_service.dart`,
`insights/services/weekly_snapshot_export_service.dart`,
`dreams/services/dream_theme_service.dart` (read).

**Acceptance:** a weekly/monthly recap generated with synthetic dream
entries includes a themes section matching `computeSummary`'s output for
that window; a recap with no dream entries omits the section rather than
showing an empty one.

**Size:** S–M.

---

## Sequencing summary

| Phase | Items | Why this order |
|---|---|---|
| 1 | #1 bandwidth, #2 outcome loop, #3 constitution audit | All three touch the same `NeuraAutonomyPolicy` assembly point in `neura_intelligence_controller.dart` — do them as one focused pass so the suppression plumbing is written once, not three times. Start with #3's audit since it may change how #1/#2 are framed. |
| 2 | #4 promise reminders, #5 distress detector, #6 streak joy, #7 module-hint audit | Fully independent of each other and of Phase 1; can run in parallel or in any order. #7 starts as investigation — do it early enough that its findings (real gap vs. already-fine) are known before anyone assumes the worst. |
| 3 | #8 `care/` surface consolidation (text + navigation), #9 constitution work-hours (contingent on #3), #10 recap dream themes | Lowest urgency; #9 is explicitly blocked on #3's outcome and should not be scheduled before it resolves. #8 grew in scope during the post-merge audit but is still independent of #9/#10. |

Every item that traces a "does X actually call Y" question is deliberately
scoped as investigate-then-fix, not fix-on-assumption — round 1's dream
signal and this round's persona/audience finding both show that reading the
real call graph changes the correct scope more often than not.
