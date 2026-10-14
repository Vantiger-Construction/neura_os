# Google Play Listing Materials

**Status: review draft for a testing track; publication blocked.** Audited on
2026-10-14 against `Neura` commit `90146013940f452f7de845598ea8e278a997a385`.
Android debug packaging has passed automated checks; physical-device acceptance
and a selected Play-ready distribution package are not established. See [the
claims and publication record](STORE_LISTING_AUDIT.md).

These fields describe a restricted mobile testing scope. Verify every listed
flow in the selected Android build and remove any unavailable feature before
use. Keep this maintainer notice out of the store description.

## App name

```text
Neura Companion OS
```

## Short description

```text
A kind AI companion for reflection, personal notes and everyday planning.
```

## Full description

```text
Meet Neura, an AI companion in development for personal reflection and practical everyday help. Neura Companion OS brings together text journaling, your own mood check-ins, fixed guided activities and themed spaces in an early testing version.

A companion at your pace
Neura's companion style is designed to be kind, patient and honest. Ask about a day-to-day task, think through an idea, or request help breaking a concern into manageable steps. Her style encourages clear explanations and your own decisions. AI replies can be mistaken; use your own judgement.

What to explore
- Write text journal entries and reopen saved responses.
- Choose a mood rating and an optional note, then revisit your recorded check-ins.
- Try quiet writing, grounding prompts and a one-small-plan activity.
- Move between themed spaces for conversation and reflection.

Privacy and controls
Text journaling and fixed guided activities are designed to work locally. Cloud AI conversation requires an internet connection and a configured AI provider. Review and approve each cloud chat request before it is sent. Safe Mode keeps microphone capture off.

Testing scope
This mobile testing version does not offer a full offline language model, automatic cross-device synchronization or public community feeds. Features remain under evaluation; availability can change between test builds.

Neura provides general information and reflection tools. She does not diagnose conditions, provide treatment or replace a qualified professional or emergency service. For health concerns, speak with a qualified professional.
```

## Developer contact and privacy fields

- **Privacy policy URL:** Unset; a verified public policy page that applies to
  the selected build and its actual data handling is required.
- **Support email:** The existing feedback destination is recorded in the audit;
  confirm monitoring and suitability before assigning the console field.
- **Developer website candidate:** [Existing project website](https://neura-companion-os.justtick8.chatgpt.site).
  Project control and public deployment are confirmed; anonymous accessibility
  and content suitability remain to be checked. Do not treat it as the policy.

The previous `neura.com/privacy` destination is not approved. No replacement
policy or support URL has been invented. See [STORE_LISTING_AUDIT.md](STORE_LISTING_AUDIT.md)
for the exact publication dependencies.

Privacy/support follow-up: [revised privacy draft](PrivacyPolicy.md),
[support draft](Support.md), and [publication review](PRIVACY_SUPPORT_PUBLICATION_REVIEW.md).
The privacy URL and public contact assignment remain blocked until the exact
deployed page and monitored contact are verified.

## Listing assets and release handoff

- Produce an actual feature graphic. `marketing/feature_graphic.png` does not
  exist; the repository contains a placeholder text file instead.
- Capture Android screenshots from the selected accepted build;
  `screenshots/android/` currently contains only `.gitkeep`. Use Android images
  for this listing and keep concept imagery clearly separate.
- Validate the selected signed Play distribution package, device installation,
  offline local flows, permissions, lifecycle, cloud approval/cancellation and
  local data controls. A CI debug APK does not establish store readiness.
- Complete accurate Data safety, Health apps declaration, content/age-rating,
  app-access and contact details, including third-party processing. Review
  account-deletion requirements if account creation is enabled. No answers,
  age rating or submission have been supplied here.
- Explain provider setup and any costs. Do not imply a bundled mobile offline
  model, free AI access or a verified subscription. Recheck copy before
  production promotion; do not submit or merge automatically.

Google Play's [listing fields](https://support.google.com/googleplay/android-developer/answer/9859152)
allow 30 characters for the name, 80 for the short description and 4,000 for the
full description; listings also appear on testing tracks. A generic
"Promotional Text" field is not part of these main listing fields, so the former
heading has been removed. Review [User Data](https://support.google.com/googleplay/android-developer/answer/10144311)
and [Health Content and Services](https://support.google.com/googleplay/android-developer/answer/16679511)
when completing the publication dependencies.

