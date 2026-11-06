# A Neura who feels familiar to each person

Neura should have a recognizable, kind character and a different relationship
with each person. The experience should come from consistent behavior, useful
continuity and personal choice. She must remain honest about being an AI.

## First implementation: a coherent personal style

Open Settings → Neura's Personas → the shared tone controls → Your Neura.
Choose Calm companion, Playful spark, Steady coach or Thoughtful guide, then
adjust warmth, directness, humor, energy and depth. The examples are handwritten
previews. Draft changes take effect only after Save persona; resetting the draft
also requires saving.

The existing local preference store retains the selected numbers. The existing
prompt builder applies them to replies, including explicitly selected offline
Ollama replies. Current-mood adjustments now reach the actual prompt wording
instead of only the response-style numbers. Offline chat continues to exclude
stored mood and unapproved persistent memory.

The shared Flutter motion engine and floating Windows mascot also use energy,
warmth and humor. Energy shapes breath, sway and idle timing; warmth biases aura
color; humor changes idle gesture weights. These are presentation preferences,
not inferred emotions or activity. Personality does not fabricate listening,
thinking or speaking. Default values preserve balanced motion. Still, reduced
motion, background, recovery and Safe Mode retain their existing precedence.

Preferences describe the companion's delivery, not a psychological profile of
the person. The normal installation retains its existing single style. An
explicitly enabled [local profile workspace](LOCAL_PERSONALITY_PROFILES.md)
now keeps several chosen styles separately in an encrypted registry and opens
fresh text chats after selection. It excludes installation-wide private stores
and voice permissions. Review its opt-in and exit limits before enabling it;
it does not authenticate people or synchronize profiles.
It adds no training, automatic preference inference, model downloads, network
requests, journal access, microphone access or background conversations.
The Unity prototype's relay is unchanged.

For a visible mouth during ordinary speech, select the optional
[expressive face](EXPRESSIVE_AVATAR.md). It combines the existing personal body
motion with event-driven articulation in the main app's stage and room panel.

## Next milestones toward individuality

1. **User-approved continuity.** Use scoped encrypted companion memory to retain
   chosen preferences, ongoing goals and useful shared context. Let the person
   inspect, correct and forget each item. Recall must obey the actual destination
   permission; local-only notes must not enter a cloud request.
2. **Learning by feedback.** Offer explicit feedback such as “less joking” or
   “shorter answers.” Preview the proposed adjustment, apply it only on approval,
   and allow undo. Avoid silently building profiles from private conversations.
3. **Personal rituals.** Let the person choose a greeting, a daily check-in or a
   quiet working routine, including when it may run. A missed visit never earns
   guilt, punishment or claims of loneliness. Proactive audio needs its own opt-in.
4. **Consistent identity across devices.** Give each person a scoped encrypted
   profile and explicitly paired devices. Switching profiles must cancel old
   turns and revoke memory access before the next person's session begins.

Acceptance should compare two synthetic users with different preferences and
authorized histories: each receives appropriate, distinct replies while Neura's
core kindness and honesty remain stable. Neither sees the other's memories.
Changing a preference is visible and reversible; revoked or forgotten memories
cannot reappear. Emotional attachment and time spent in the app are not success
metrics; usefulness, continuity, correctness and user control are.

## Validation boundaries

Automated tests cover distinct prompt styles, local reload, rejected saves,
draft isolation, reset, malformed inputs, bounded differentiated motion, mood
adaptation, offline prompt budgets and the existing motion safety gates.
They do not establish actual local-model conversation quality or visual/audio
acceptance on Windows and Android. Those need device testing with synthetic
conversations, including interruptions, returning from background and quiet
preferences. No larger model or changed memory admission limit is required by
this implementation.
