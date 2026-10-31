# Neura companion upgrades — October 2026

This review branch combines the existing memory, planning/recovery, routine/privacy,
and shared avatar work, then adds six companion capabilities. It is source for
review and platform validation, not a claim that an installed app has been upgraded.

## What to try

| Upgrade | Entry point | Behavior |
| --- | --- | --- |
| Conversation continuity | Main chat → Offline Ollama → Conversation thread | Opt in to a visible, editable topic and latest correction. Short verbatim user text survives ordinary history trimming within the existing byte budget. |
| Teach Neura | Main chat menu → Teach Neura | Review locally saved encrypted notes, correct their text, or forget an individual note with separate confirmation. |
| Everyday follow-through | Main chat → Plan my day | Approve a plan, focus on the next unfinished step, pause/resume, or make the current step smaller while preserving completed progress. |
| Offline reference shelf | Main chat menu → Offline reference shelf | Select a text document, find exact passages locally, and on Windows explicitly approve those passages for one local Ollama answer. |
| Responsive presence | Existing room avatar and Windows floating mascot | Shared body motion, bounded gestures and speech beats; speech completion/Stop clears pending speech gestures. Still, reduced motion, background and safety/recovery states stop motion. |
| Continue on another device | Daily planner → Continue on another device | Export one approved plan as an encrypted packet; import and inspect it on Windows or Android, then explicitly approve the new plan. |

## Conversation and memory

The conversation thread is an optional session brief, not a generated summary or
new long-term memory. Its topic and latest correction are capped at 160 UTF-8
bytes each; oversized turns are never truncated into a different claim. It fits
inside the existing compact/standard conversation limits. The newest complete
user message takes priority if there is no room for the brief. Background,
safety/recovery and explicit conversation/tool changes clear the brief.

Corrections and deletion use fresh operation-specific encrypted-memory permission.
A mutation revokes older review/recall grants before the write; corrections record
new user-authored provenance. A revoked asynchronous correction cannot overwrite
the original note. Leaving the foreground clears memory drafts and reviewed lists.
Ordinary offline chat still cannot recall stored notes automatically.

## Document references

The shelf holds one explicitly selected UTF-8 TXT, MD, CSV or JSON document, up to
32 KiB, in memory. It does not scan folders, ingest PDFs, build a persistent index,
or synchronize documents. Retrieval uses English/alphanumeric keyword overlap,
returns up to three exact source passages with line numbers, and may miss relevant
information. No match means no answer is generated.

The user sees the passages before choosing **Use these passages for one local
answer** on Windows. Only that question and those passages enter a single local
request, with no previous chat, persistent notes, tools or cloud fallback. The
existing input and full-response guardrails stay in place. The grant is single-use
and invalidated by source changes, Stop, background or safety/recovery. Late native
results cannot restore a cleared answer.

Reference replies now use a conservative quotation-only protocol. Local Ollama
selects passages using a bounded JSON response; every selected number and complete
text must match an approved passage exactly. Neura renders the original passage
and its original line number. Changed quantities, negations, shortened quotations,
unknown references, extra explanations, malformed responses or mixed valid/invalid
evidence withhold the entire reply and show explicit uncertainty. Empty evidence
also shows uncertainty, without an automatic retry or cloud fallback. Model-written
explanations are withheld even when they carry valid citation numbers.

Whole-passage quotation matching establishes text identity, not factual entailment,
truth, relevance, or completeness. Keyword retrieval can split a long line or miss
conditions elsewhere in the source. Even an exact selection can be irrelevant,
partial, outdated or contradictory. Every successful selection explicitly says that
Neura cannot establish whether it fully answers the question and asks the user to
check the complete source. Source previews stay visible and unchanged. This trades
free-form answers for inspectable evidence; real-model JSON compliance and usefulness
remain acceptance work on the Windows laptop, within the existing memory budget.

## Manual Windows–Android continuation

Only the goal, ordered steps and completed-step indices are transferred. The
payload uses the existing cryptography package's AES-GCM-256 implementation, a
fresh random key, authenticated version context, strict bounded parsing and a
30-minute validity window. The key is separate from the encrypted packet.

Copy the key first, then save the encrypted `.neuratask` file. Move that file by
your chosen channel. On the receiving device, copy the key before opening Neura,
load the packet and paste the key without leaving the transfer screen. System
clipboards may synchronize. Keep the key separate from the packet when sharing.
An explicit file save hands only ciphertext to the operating-system picker.
Loading a file clears the previous transfer, including its key, before opening
the picker. Paste the receiving key **after** the selected packet appears.

Import produces a preview, never execution or inherited approval. Progress is a
claim from the sender for the user to review. There is no automatic pairing,
network discovery, cloud transfer, device-trust change or background task runner.
Screens clear plaintext and key fields on background/safety/recovery; this is not
a guarantee of zeroized process memory. Existing exported files/clipboard copies
cannot be revoked by an in-app wipe; expiry is checked by the importing app and
does not erase a packet held by someone who has its key.

The import picker has a separate, revocable request identity. Its first OS
lifecycle round trip still clears every transfer field and invalidates ordinary
work. A selection delivered before `resumed` waits without reading its stream;
only the current request may load ciphertext on the current, foreground route.
Clear, edits, Safe Mode, recovery, detach, disposal, or a second background trip
after the first resume invalidate that request. Backgrounding during the file
read also invalidates it. Only one picker request may be pending.

`flutter test test/planning/neura_task_transfer_picker_test.dart` uses a controlled
picker and legal Flutter lifecycle sequences. It covers both return orderings,
cancellation/retry, revocation and stale errors, bounded streams, malformed files,
wrong keys, expiry and explicit planner approval. These simulations do not
establish Android's actual picker event order or successful device-to-device use.
On the Samsung Android 16 test phone, verify selection/cancellation, Home and
return, Safe Mode/recovery, and rejection of expired/wrong-key packets. Separately
transfer an approved synthetic plan Windows → Android and Android → Windows;
confirm progress stays a preview until fresh approval. Record the app SHA,
Android version and observed lifecycle order without recording packet keys.

## Motion and speech

The shared body replaces the room's duplicate idle bob controller. Main and
floating-window sampling honor active state and motion preferences. The floating
window starts inactive until a main-engine body snapshot permits animation;
malformed cues are rejected before applying any component. Native TTS completion
and Stop end speech beat scheduling. Existing startup-speech restrictions remain.
These are visual responsiveness improvements, not a measured model-latency gain.
Replies are still screened in full before display/speech; raw token streaming is
not enabled.

## Integrated sources

- Default `Neura`: `1beaadf072a0350165b6464bc620920549f4a2e5` (security baseline).
- PR #141 memory: `bff9a701bda7c2361f4fc07fb5b34c7a38e510d7`.
- PR #147 planning/recovery: `acd7cdd77401ba85ac3de867927155fbcb58d103`.
- PR #148 routine/privacy: `bf616e86abf081dd65bf2000b102f8cc6bc61307`.
- PR #149 shared motion: `cd4e448bfdaac1e28c13c1cbe0cecc8bf90bdd58`.

The integration keeps both wipe-fixture interception hooks and combines shared
room motion with the earlier lifecycle, reduced-motion and accessibility behavior.
No dependency upgrades, model changes, scanner exemptions or action-pin changes
are required.

## Validation and remaining acceptance

Validation results are recorded in the pull request after running the combined
tree. CI includes the new reference, transfer, continuity and motion tests. Memory
release contracts continue to run the complete encrypted-memory suite. The Windows
preview workflow bundles this guide and records the exact source SHA.

Physical Windows speech/model inference, laptop RAM and latency, Android picker
and clipboard behavior, and an actual two-device handoff still require device
acceptance. Unit/widget tests use synthetic native adapters and do not establish
those results. Existing Windows speech acceptance issue #32 remains open; no
production release or merge is implied by this branch.
