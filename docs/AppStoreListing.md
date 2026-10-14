# Apple App Store and TestFlight Materials

**Status: review draft; publication blocked.** Audited on 2026-10-14 against
`Neura` commit `90146013940f452f7de845598ea8e278a997a385`. iOS project files exist,
but no verified iOS package or physical-device acceptance was found. Shared
Flutter implementation and Windows/Android checks do not establish an iOS
release. See [the claims and publication record](STORE_LISTING_AUDIT.md).

Use TestFlight for Apple beta testing. The future App Store fields below are
held until the selected iOS release passes every advertised flow. Keep this
maintainer notice and dependency notes out of customer copy.

## Future App Store fields

### Name

```text
Neura Companion OS
```

### Subtitle

```text
Reflection and everyday help
```

### Promotional text

```text
Make room for reflection and a manageable next step with Neura: a kind AI companion, personal journaling and guided activities at your own pace.
```

### Description

```text
Make room for a moment of reflection and a manageable next step with Neura Companion OS.

Meet Neura, an AI companion designed to be kind, patient and honest. Talk through everyday questions, organise your thoughts, or ask for help breaking a task into smaller steps. Her companion style encourages clear explanations and your own decisions.

Your everyday space
- Write text journal entries and revisit saved responses.
- Choose your own mood rating and an optional note, then review your recorded check-ins.
- Explore quiet writing, grounding prompts and a one-small-plan activity at your own pace.
- Choose themed spaces for conversation and reflection.

Privacy and choice
Text journaling and fixed guided activities are designed to work locally. Cloud AI conversation requires an internet connection and a configured AI provider. Review and approve each cloud chat request before it is sent. Safe Mode keeps microphone capture off.

AI replies can be mistaken. Neura provides general information and reflection tools. She does not diagnose conditions, provide treatment or replace a qualified professional or emergency service. For health concerns, speak with a qualified professional.
```

### Keywords

```text
journal,reflection,mood,check-in,planning,focus,grounding,personal notes
```

### URLs

- **Privacy Policy URL:** Unset; a verified public policy page is required.
- **Support URL:** Unset; a verified public support page with actual contact
  information is required.
- **Marketing URL candidate:** [Existing project website](https://neura-companion-os.justtick8.chatgpt.site).
  Project control and public deployment are confirmed; anonymous accessibility
  and content suitability remain to be checked. It is not a verified privacy
  or support destination.

Do not reuse the previous `neura.com` links. Exact dependencies and the existing
feedback contact are in [STORE_LISTING_AUDIT.md](STORE_LISTING_AUDIT.md).

## TestFlight beta description draft

Held until an accepted iOS test build exists; no TestFlight invitation or public
beta availability is claimed.

```text
Help evaluate Neura Companion OS: an AI companion in development for everyday questions, reflection and manageable next steps.

The testing focus is text journaling, your own mood check-ins, quiet writing, grounding prompts, a one-small-plan activity and themed spaces. Cloud chat requires a configured AI provider, internet access and approval of each request.

Features remain under evaluation. Full offline AI, automatic cross-device synchronization and public community feeds are not offered in this mobile testing scope. Neura provides general information, not diagnosis, treatment or emergency care.
```

## What to Test draft

```text
Using sample information, try saving and reopening a text journal entry, recording a mood check-in, and completing or leaving each guided activity. Check navigation between rooms, enlarged text and reduced-motion preferences.

Check that temporary guided writing clears when you leave or background the app. Verify Safe Mode keeps microphone capture off and that cancelling a cloud request sends no request. Report permission, save, navigation or restart problems privately, without personal writing, recordings or credentials.
```

## Release handoff

- Validate the selected iOS build on physical devices before using these fields;
  remove any flow the build cannot supply. Evaluate model replies separately
  from prompt and widget tests.
- Capture screenshots from that build. `screenshots/ios/` currently contains
  only `.gitkeep`; conceptual art is not evidence of the shipped interface.
- Complete accurate App Privacy, content/age-rating and reviewer-access details,
  including third-party processing and provider setup or costs. No privacy
  label, age rating, price or subscription entitlement is established here.
- Obtain the policy and support destinations in the audit. Submit only through
  a separately authorized store workflow; do not merge automatically.

Limits checked against Apple's [app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
and [platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information):
name/subtitle 30 characters, promotional text 170 characters, description 4,000
characters, keywords 100 bytes. Apple's [review guidelines](https://developer.apple.com/app-store/review/guidelines/)
direct beta testing to TestFlight and require accurate, functional metadata.
