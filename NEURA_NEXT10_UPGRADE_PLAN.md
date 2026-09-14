# Neura — Next 10 Upgrades: Implementation Plan

Grounded against the current tree (2026-09-13). Several items already have partial
infrastructure — this plan builds onto that instead of duplicating it. Each item
lists: what exists today, what's missing, the concrete approach, files touched,
and acceptance criteria. Phases are ordered by dependency, not by upgrade number.

---

## Phase 1 — Foundation (no user-facing risk, unlocks later phases)

### 1. Close the loop: Opportunity Radar outcomes → Signal Graph

**Exists:** `intelligence/models.dart` already has `NeuraSuggestionOutcome`
(`shown/acted/dismissed/evaluated`) recorded per `DecisionReceipt`, surfaced in
`neura_intelligence_controller.dart` and `intelligence_center_screen.dart`.
`signal_graph.dart` (`NeuraSignalGraph` / `_WeightedObservation`) has no consumer
of that outcome — recommendations never get better from being accepted/declined.

**Missing:** a feedback edge from recorded outcomes back into signal weighting.

**Approach:**
- Add `NeuraSignalGraph.recordSuggestionOutcome(specialistId, outcome, deltaAfter)`
  that nudges a per-specialist confidence multiplier (bounded, decaying), not raw
  mood/journal text — keeps the existing "no raw text" privacy boundary.
- Call it from `neura_intelligence_controller.dart` at the same point outcomes are
  currently persisted (lines ~257–279), after enough time has passed to measure
  `deltaAfter` (next mood/quest signal tick).
- Store the per-specialist multiplier in the same bounded ledger style already used
  by `consent_ledger.dart` (operational metadata only).

**Files:** `intelligence/signal_graph.dart`, `intelligence/neura_intelligence_controller.dart`,
`intelligence/opportunity_radar.dart` (read the multiplier when scoring).

**Acceptance:** repeatedly dismissing a specialist's suggestions measurably lowers
its future score within N days; a unit test drives synthetic outcome sequences and
asserts monotonic confidence movement in both directions.

**Size:** M.

---

### 2. Decision Receipt explorer

**Exists:** `intelligence_center_screen.dart` already renders a `_ReceiptTile` list
with outcome, score, reasons, evidence count, and a clear-history action.

**Missing:** it's a flat recent-list, not a browsable history — no filter by
specialist/outcome/date, no link from a Timeline Vault entry to the receipt that
caused it.

**Approach:**
- Add filter chips (specialist, outcome, date range) above the existing list in
  `intelligence_center_screen.dart`; reuse `_ReceiptTile`.
- Extend `reliability/timeline_vault.dart` entries that originated from an
  autonomy-kernel action to carry the receipt id, and add a tap-through from
  Timeline Vault → filtered receipt view.
- No new storage: this is UI + a foreign-key-style id already available on
  `DecisionReceipt` (`evidenceIds`).

**Files:** `intelligence/intelligence_center_screen.dart`, `reliability/timeline_vault.dart`,
`reliability/timeline_vault_io.dart` / `_web.dart`.

**Acceptance:** from any Timeline Vault entry produced by the Autonomy Kernel, one
tap reaches the exact receipt that authorized it.

**Size:** S.

---

## Phase 2 — Trust & safety (wires existing modules together)

### 3. Crisis escalation, policy-gated

**Exists:** `care/models/crisis_playbook.dart`, `care/services/crisis_playbook_service.dart`,
`care/screens/crisis_playbook_detail_screen.dart` already model and display crisis
resources. `guardrails/support_resources.dart` already exists. None of this is
currently *triggered* by the Signal Graph — it's manually opened by the user.

**Missing:** an automatic, policy-gated surfacing when mood signals cross a severe
threshold, using the same Autonomy Kernel machinery as every other proactive action.

**Approach:**
- Register a new capability in `intelligence/capability_registry.dart`:
  `crisis_playbook_surface`, classed as **critical** — per the existing rule set in
  `NEURA_CONSOLIDATED_UPGRADES.md` ("critical effects are blocked from autonomous
  execution"), so this always requires human confirmation; the kernel only decides
  *whether to ask*, never to act.
  Wire the trigger condition into `intelligence/opportunity_radar.dart` as a new
  specialist that reads the existing bounded mood signal (no new raw-text access)
  and proposes (never pushes) `care/screens/crisis_playbook_detail_screen.dart`.
- Respect Safe Mode, quiet hours, and cooldown exactly as `autonomy_kernel.dart`
  already does for other cards — do not special-case crisis to bypass quiet hours;
  severity threshold should be conservative enough that this is rare.

**Files:** `intelligence/capability_registry.dart`, `intelligence/opportunity_radar.dart`,
`intelligence/autonomy_kernel.dart` (policy entry only), `care/services/crisis_playbook_service.dart`.

**Acceptance:** a synthetic severe-mood-signal test produces exactly one
confirmation-gated card, never an autonomous navigation; declining behaves like
any other decline (no repeated nagging, respects `recent-decline` policy).

**Size:** M. **Needs a product/clinical-content review before ship** — flag for
human sign-off on threshold and copy, not something to auto-merge on green CI.

---

### 4. Trusted-contact sharing channel

**Exists:** `care/models/trusted_contact.dart` + `care/services/trusted_contacts_service.dart`
already store emergency/professional contacts locally (SharedPreferences-backed).
`relationships/services/relationship_insight_service.dart` and `distress_detector.dart`
exist but are self-contained (insights shown only to the user).

**Missing:** any actual *sharing* — right now "trusted contact" just means "a
phone number I can tap," not "a scoped export."

**Approach:**
- Model the share as an Action Loom capability (`intelligence/action_loom.dart` +
  `approval_broker.dart`), exactly like the existing cloud-tool mood-history share:
  scope = mood trend only (dates + numeric scores, same shape already used for
  cloud-tool sharing), explicit confirmation per share, revocable via
  `consent_ledger.dart`.
- Delivery mechanism for v1: generate a shareable read-only summary (PDF/text)
  the user hands to their contact themselves (share sheet) — no backend send, no
  new server component, keeps this in the same "local-first, explicit action"
  posture as the rest of the app.
- Add a "Shared history" panel to `trusted_contacts_service.dart`'s contact detail
  so the user can see and revoke past shares.

**Files:** `care/services/trusted_contacts_service.dart`, `care/models/trusted_contact.dart`,
`intelligence/action_loom.dart`, `intelligence/consent_ledger.dart`, new
`care/services/contact_share_service.dart`.

**Acceptance:** a share requires fresh approval (per existing `fresh_approval_lease.dart`
rules), only ever exports the same bounded fields already permitted for cloud
sharing, and is listed/revocable afterward.

**Size:** M–L.

---

## Phase 3 — Experience upgrades

### 5. Dream ↔ Mood correlation (privacy-preserving)

**Exists:** `dreams/services/dream_theme_service.dart` already extracts
`DreamThemeSummary` (top tags/words/mood) **locally, on-device**, from
`dreams/models/dream_entry.dart`. This is not fed into `signal_graph.dart` at all
today — dreams and mood are two silos.

**Missing:** wiring `DreamThemeSummary` into the Signal Graph as a bounded,
non-sensitive signal (tag/mood category only — never `topWords` raw text, per the
existing "raw journals/dreams are not read" rule).

**Approach:**
- Add a `DreamSignalAdapter` (mirrors `intelligence/runtime_signal_adapter.dart`)
  that emits only `topMood` category and tag *counts* (never raw words) into
  `NeuraSignalGraph`, on the same freshness/confidence/sensitivity contract as
  mood and quest signals.
- Opportunity Radar can then propose things like a gentle Dream Visualizer nudge
  when a recurring theme correlates with a mood dip — same specialist pattern as
  existing ones, no new UI paradigm.

**Files:** new `intelligence/dream_signal_adapter.dart`, `intelligence/signal_graph.dart`
(register source), `dreams/services/dream_theme_service.dart` (expose summary
stream), `intelligence/opportunity_radar.dart` (new specialist).

**Acceptance:** signal graph inspector (`intelligence_center_screen.dart`) shows a
dream-sourced signal with correct freshness/confidence; raw dream text is
verifiably never touched by grepping the adapter for any field but `topMood`/tag
counts.

**Size:** M.

---

### 6. Live expressive TTS for conversational responses

**Exists:** `services/neura_tts_service.dart`, `services/neura_voice_pack.dart`,
`integrations/tts/neura_flutter_tts_viseme_bridge.dart`, and
`avatar/viseme/neura_viseme_engine.dart` already do offline clip playback + live
mic-driven viseme animation (`avatar/neura_mic_driver.dart`). `voice_lab_screen.dart`
exposes this only as a manual demo, not for real Neura responses.

**Missing:** routing actual chat/journaling responses from `neura_link/brain_link.dart`
through TTS + viseme in real time, with barge-in.

**Approach:**
- Extend `neura_link/conversation_controller.dart` to optionally stream response
  text chunks into `neura_tts_service.dart` as they arrive over SSE (the existing
  streaming path per `NEURA_CONSOLIDATED_UPGRADES.md`'s "SSE streaming,
  cancellation and barge-in"), driving `neura_viseme_engine.dart` off TTS phoneme
  timing instead of live mic input during playback.
- Cancellation: reuse the existing SSE cancel/barge-in hook so a user talking over
  Neura stops playback the same way it already stops text streaming.
- Gate behind a Settings toggle (`screens/neura_voice_settings_screen.dart`) — off
  by default until validated, since it's the most latency- and battery-sensitive
  item here.

**Files:** `neura_link/conversation_controller.dart`, `services/neura_tts_service.dart`,
`avatar/viseme/neura_viseme_engine.dart`, `screens/neura_voice_settings_screen.dart`.

**Acceptance:** enabling the toggle produces spoken responses with lip-synced
avatar during Focus Office and normal chat; barge-in interrupts audio within one
sentence boundary; disabling the toggle fully reverts to text-only with zero TTS
initialization (respects the existing lazy/policy-gated init pattern).

**Size:** L.

---

### 7. Sync conflict review UI

**Exists:** conflict-aware sync already ships (`feat: resolve sync conflicts by
revision time`, `feat: track journal revision timestamps`) plus
`screens/sync_status_screen.dart` and a reliability dashboard
(`Add a local-first sync reliability dashboard`). Resolution is currently silent —
last-revision-wins with no visible diff.

**Missing:** a record of *what* was overwritten, and a place to see it.

**Approach:**
- In `services/sync_service.dart`, when a conflict resolves by revision time,
  write a bounded conflict record (entry id, both revision timestamps, which side
  won) — not full content diffs, to avoid duplicating encrypted journal content
  into a new unencrypted store. Reuse the Timeline Vault pattern for this ledger.
- Add a "Resolved conflicts" section to `screens/sync_status_screen.dart` listing
  these records, with a deep link to the affected journal entry so the user can
  manually compare if they want full content (the entry itself still holds
  history if the vault versions it — check `modules/vault/memory_vault_store.dart`
  before assuming; if it doesn't version, note that as a prerequisite, not part of
  this item's scope).

**Files:** `services/sync_service.dart`, `screens/sync_status_screen.dart`,
`reliability/timeline_vault.dart`.

**Acceptance:** every silent auto-merge produces one visible, timestamped record
in Sync Status; no plaintext journal content enters a new unencrypted store.

**Size:** S–M.

---

### 8. Glanceable widget surface

**Exists:** nothing — no `home_widget`-style package or platform widget code found
anywhere in `lib/` or `android/ios/windows` platform folders.

**Missing:** everything; this is genuinely new surface area, and the only item
here that needs a new dependency and platform-specific code (Android App Widget +
iOS WidgetKit at minimum; Windows/desktop can skip — no OS widget surface there).

**Approach:**
- Add `home_widget` (or platform channel equivalent) behind a capability flag
  consistent with `intelligence/capability_registry.dart`'s policy-gating.
- Widget shows: last mood check-in state, a tap target to record a new one, and
  (only if Opportunity Radar already independently decided to show a card in-app)
  a mirrored gentle nudge — the widget must never originate a decision the
  Autonomy Kernel hasn't already approved; it reflects state, it doesn't compute.
- Respect quiet hours / Safe Mode by having the widget read the same latched
  state `guardrails/guardrails.dart` exposes, refreshing on the OS's normal widget
  update cadence (no custom background service).

**Files:** new `os_shell/widgets_bridge/` package, Android `AppWidgetProvider`,
iOS WidgetKit extension target, `mood/services/mood_state_service.dart` (read-only
export).

**Acceptance:** widget reflects real mood-checkin state within one OS refresh
cycle; widget never shows a nudge that wasn't already independently approved for
in-app display; Safe Mode blanks the widget to a neutral state.

**Size:** L — largest single item due to two native platform integrations.

---

## Phase 4 — Resilience

### 9. Scheduled auto-backup + restore verification

**Exists:** `services/portable_vault_backup_service.dart`, `portable_backup_codec.dart`
already do encrypted export/import on manual trigger. No scheduling found
(confirmed — no `Timer`/`WorkManager`/periodic hooks in that service).

**Missing:** (a) silent periodic backup without a manual export, (b) a restore
dry-run that verifies integrity before the user actually needs it.

**Approach:**
- Add `PortableVaultBackupService.runScheduledBackupIfDue()`, called from the
  existing app-resume/startup health path (`startup/` module) rather than a new
  background service — matches the "lazy, policy-gated" init philosophy already
  used for audio/TTS/Rust Swarm.
- Add `verifyBackupIntegrity(archive)` that decrypts and checksums without writing
  data back into the live vault — surfaces failures in Diagnostics immediately
  rather than at restore time.
- Gate frequency and destination (local disk only, v1) behind a Settings toggle;
  default off until the verify path has test coverage, since silent backups
  touching encrypted vault data are exactly the kind of change that deserves
  caution.

**Files:** `services/portable_vault_backup_service.dart`, `services/portable_backup_codec.dart`,
`startup/` (hook point), Diagnostics screen (surface verify failures).

**Acceptance:** a scheduled backup runs without user action once enabled; a
deliberately corrupted archive fails `verifyBackupIntegrity` and is surfaced in
Diagnostics, never silently accepted.

**Size:** M.

---

## Sequencing summary

| Phase | Items | Why this order |
|---|---|---|
| 1 | #1 loop-closing, #2 receipt explorer | Pure additive plumbing on existing intelligence module; no new capabilities, safe to land first, and #3/#4 reuse the same capability-registry pattern once it's fresh in review. |
| 2 | #3 crisis escalation, #4 trusted-contact sharing | Both are new **capabilities** through Action Loom/Autonomy Kernel — highest scrutiny (clinical content, data sharing), do them together while that machinery is top of mind, but expect human sign-off gates, not just CI green. |
| 3 | #5 dream signal, #6 live TTS, #7 conflict review, #8 widget | Independent of each other; #8 is the only one needing native platform work, so it can run in parallel with #5–#7 on a separate track. |
| 4 | #9 scheduled backup | Touches encrypted vault write paths — do last, after the team has re-familiarized with the encryption/backup code from earlier phases' review cycles, and ship default-off. |

Every item that introduces a new proactive behavior (#1, #3, #4, #5, #8) goes
through the existing Autonomy Kernel / Action Loom policy path rather than
inventing a parallel one — that's the main design constraint carried through this
whole plan.
