# Store listing claims and publication record

**Audited:** 2026-10-14. **Disposition:** rewritten copy is ready for review,
not store submission. Implementation, automated checks, physical acceptance and
public availability are distinct evidence levels. No store submission or
automatic merge was performed.

## Baseline and release evidence

Source: [Neura `90146013940f452f7de845598ea8e278a997a385`](https://github.com/Vantiger-Construction/neura_os/tree/90146013940f452f7de845598ea8e278a997a385),
version `1.5.0+1`. Relative source links below were inspected at this baseline.

| Evidence checked | Result and scope |
| --- | --- |
| [Default-head coverage 38513524181](https://github.com/Vantiger-Construction/neura_os/actions/runs/38513524181) | Flutter log reports 798 passing tests; Rust all-target coverage jobs pass on Linux and Windows. These are automated results, not device or model-quality trials. |
| [Merged PR #128](https://github.com/Vantiger-Construction/neura_os/pull/128) | Head `42f3caffa16449b971ac9dd6096305d2107c1aee` has tree `cf309ed5bf9cbfd59799eb6ca2d159a320c2d06d`, exactly matching the baseline. Its source commit identity differs. |
| [Windows 38458245875](https://github.com/Vantiger-Construction/neura_os/actions/runs/38458245875) | Passed. Log identifies tested merge `b8e6cd987f6fd1d8445ba5f0c7b97d0112652556`; its tree also exactly matches baseline. Publisher reports three download-verified Windows assets. This is package/runner evidence, not installed-app acceptance. |
| [Android 38458245608](https://github.com/Vantiger-Construction/neura_os/actions/runs/38458245608) | Passed on PR #128's recorded head, including debug APK build, verification, preservation and required publication. Its job log could not be retrieved during this audit; the actual checkout/package bytes were not independently reconciled or downloaded here. Not Play readiness. |
| PR #128 [State Matrix 38458245518](https://github.com/Vantiger-Construction/neura_os/actions/runs/38458245518), [Consent 38458245595](https://github.com/Vantiger-Construction/neura_os/actions/runs/38458245595), [memory 38458245486](https://github.com/Vantiger-Construction/neura_os/actions/runs/38458245486), [Ollama 38458246152](https://github.com/Vantiger-Construction/neura_os/actions/runs/38458246152) | All succeeded on the recorded PR head. Source-head tree parity is confirmed; these are not new physical-device results. Ollama fixtures and packaged launch do not establish actual model inference. |
| [Roadmap](https://app.notion.com/p/3f4cff6b3f4381f0946bce2d183d1df1), [release checklist](https://app.notion.com/p/3f4cff6b3f43811d8c45f15ab19be71d), [guided-support record](release-evidence/NEURA_GUIDED_SUPPORT_RELEASE_EVIDENCE.md) | Physical Windows/Android acceptance, offline queues and conflict-aware handoff remain open; GS-1 through GS-5 are NOT COLLECTED. No passing candidate-device result was found or inferred. |
| `ios/` and [RunnerTests.swift](../ios/RunnerTests/RunnerTests.swift) | Scaffold/template test only for this evidence scope. No verified iOS package, TestFlight delivery or physical iOS acceptance found. |

The October 13 roadmap predates #128's merge; newer CI results do not close its
device-only gates. PR #129's startup animation remains an open draft outside this
baseline. No startup-speed, animation-quality, voice-latency or inference-speed
promise has been added.

## Claims corrected

| Original claim / implication | Source and evidence | Revised treatment |
| --- | --- | --- |
| Advanced AI wellness/productivity; better habits; "Unlock your best self" | [Charter](../lib/persona/models/neura_character_charter.dart), [prompt builder](../lib/persona/services/neura_prompt_builder.dart), [charter tests](../test/persona/neura_character_charter_test.dart): intended behavior and wiring, not demonstrated outcomes. | Describe a kind, patient, honest companion designed for everyday help. No superiority, clinical benefit or guaranteed improvement. |
| Daily rituals and visual analytics | [QuestStore](../lib/modules/quests/quest_store.dart) records local completions/streaks; [Weekly Snapshot](../lib/insights/screens/weekly_snapshot_screen.dart) charts recorded mood scores; [journal prompts](../lib/services/journal_prompt_service.dart) are fixed content. | Advertise fixed reflection activities and recorded check-ins. No comprehensive AI habit coaching or forecasting. Device acceptance remains open. |
| Text journaling | [Journal screen](../lib/screens/journal_prompt_screen.dart), [local store](../lib/services/local_journal_store.dart), [save/reopen/retry tests](../test/screens/journal_save_workflow_test.dart) are implemented; tests are included in the passing default suite. | Retain local text writing/reopening; require save/restart acceptance on the selected platform build. |
| Voice journaling with mood insights | [VoiceJournalService](../lib/services/voice_journal_service.dart) uses Windows native or platform speech. [Speech evaluation](ON_DEVICE_SPEECH_BENCHMARK.md) rejects calling these verified on-device ASR. | Omit mobile voice/offline-speech promises. Transcript storage does not prove local audio processing; permissions, OS speech/network behavior and Windows TTS still need device evidence. |
| AI mood/emotion analysis | [Check-in](../lib/modules/mood/mood_checkin_screen.dart) accepts the user's 0-10 score/note; [history](../lib/modules/mood/mood_history_screen.dart) displays records. [EmotionAnalysisService](../lib/services/emotion_analysis_service.dart) counts keywords. | Say "your own mood rating" and "recorded check-ins". No emotion detection, diagnosis or validated mental-state inference. |
| Dream journal with AI interpretation/summaries | [Calendar](../lib/screens/dream_journal_calendar_screen.dart) and [DreamService](../lib/dreams/services/dream_service.dart) exist. [Interpretation](../lib/services/dream_interpretation_service.dart) uses symbol/keyword rules and a comment to replace them with real AI. | Remove AI dream interpretation/summaries. Existing reflective rules are not validated psychological interpretation; no device dream-flow acceptance found. |
| Community feeds/challenges | Full tree and default-branch community search find metadata/help claims, not an implemented public feed. [quests](../lib/modules/quests/quest_store.dart) and [kindness records](../lib/modules/pay_it_forward/goodwill_store.dart) are local. | Remove public social claims. Local quests do not establish shared challenges, moderation or a live community service. |
| Interactive Neura and Neuro mascots | [Registry](../lib/avatar/avatar_registry.dart) defines both, but referenced Rive/animation JSON assets are absent. [AvatarView](../lib/avatar/avatar_view.dart) has a placeholder fallback; [room presence](../lib/neura_shell/widgets/neura_room_presence_avatar.dart) supplies presentation transforms. | Retain Neura's companion identity and [themed rooms](../lib/neura_shell/models/neura_room.dart). Omit complete dual-avatar/lifelike-animation promises. Definitions and still artwork do not prove finished animated assets. |
| Offline mode with automatic sync | [SyncService](../lib/services/sync_service.dart) gates on configuration/account/connectivity/Safe Mode; [sync status](../lib/screens/sync_status_screen.dart) exposes manual sync. [Merge](../test/services/sync_service_merge_test.dart) and [session tests](../test/services/sync_service_session_test.dart) use fixtures. | Limit offline wording to local text/fixed activities. Remove automatic/seamless sync. Require live deployment, offline-queue and conflict-aware device handoff evidence. |
| Full offline AI implied on mobile | [Ollama path](NEURA_OLLAMA_CHAT.md) requires Windows, separately installed Ollama/model and memory admission; [tests](../test/services/neura_ollama_chat_test.dart) use controlled transports. | Omit full mobile offline AI. Actual model quality, RAM and latency are unmeasured. Windows/package evidence cannot be transferred to Android/iOS. |
| Privacy-first / cloud control | [AI service](../lib/services/neura_ai_service.dart) supplies approval handlers to [routing](../lib/services/neura_model_router.dart); [transaction tests](../test/services/neura_cloud_transaction_test.dart) exercise bound requests. [Safe Mode voice tests](../test/startup/native_speech_safe_mode_test.dart) cover controls. | Describe local journaling, per-request cloud-chat approval and mic-off in Safe Mode. No all-data encryption, never-leaves-device or guaranteed provider-training/retention claim. LocalJournalStore uses JSON-backed preferences; memory encryption is not universal storage encryption. |
| Wellness assistance as dependable treatment | [Guided support](NEURA_GUIDED_SUPPORT.md) contains fixed quiet-writing, grounding and one-small-plan activities; [tests](../test/modules/support/guided_support_test.dart) cover controls. The guide records no clinician review or comparative study. | General information/reflection, AI fallibility and qualified human care for health concerns. No diagnosis, treatment, emergency response or proven health outcome. |
| Store fields / graphic assets | Original Apple name/subtitle were 50/60 characters; keywords advertised unsupported analysis. Feature graphic PNG is absent; both screenshot directories contain only `.gitkeep`. | Shorten fields, use accurate keywords, remove Google Play's generic promotional-text heading, and record actual graphics as publication dependencies. |

Every retained feature requires acceptance in the selected platform build.
Removing a claim does not mean its whole module is absent: some implementations
lack the advertised scope or release evidence. Apple customer copy is a future
release draft; separate TestFlight notes describe the intended testing scope.

## Privacy and support destinations

| Destination | Observed state | Decision |
| --- | --- | --- |
| `https://neura.com/privacy` | Direct web retrieval returned no accessible content; repository references establish no project control or app-policy suitability. | Remove from both policy fields. A retrieval failure does not establish HTTP 404 or who owns the domain. |
| `https://neura.com/support` | Same retrieval limitation; no project-control or functioning support-page evidence found. | Remove from Apple Support URL. |
| [Existing project website](https://neura-companion-os.justtick8.chatgpt.site) | Connected project metadata confirms the user's public Neura Companion OS site; version 3 has a successful publication and no attached custom domains. Web retrieval returned no page content. | Preserve as a project-controlled marketing candidate. Anonymous access/content suitability remain unverified. Do not invent privacy/support routes or assign the homepage to those fields. |
| [Policy draft](PrivacyPolicy.md), [in-app legal text](../lib/src/modules/privacy/privacy_texts.dart), [Terms](TermsOfService.md) | Undated `YYYY-MM-DD` drafts, generic sync/analytics assertions and `privacy@neura.com` / `support@neura.com`; in-app Short Draft describes cloud as future and names `support@neura.app`. | Reconcile against current optional cloud paths. None proves a live, suitable policy/contact. |
| [Feedback contact](../lib/modules/feedback/feedback_screen.dart) | App mail composer targets `stevenvantiger1@gmail.com`. | Existing project-configured contact; control, monitoring and public-support suitability need confirmation. No test email was sent. |

No suitable verified privacy/support URL was found. No replacement domain,
mailbox, route or public Notion URL was invented. Private repository files and
Notion authoring links are not public policy/support destinations.

## Exact publication dependencies

1. **Privacy:** identify the actual developer/controller and monitored privacy
   contact. Finalize the selected build's disclosures for local journal/mood/
   memory, optional account/sync, cloud/speech providers, permissions, retention,
   deletion and third parties; reconcile in-app wording and draft dates/contacts.
   Publish a project-controlled public HTTPS policy page and verify the exact
   URL without sign-in, geofencing or edit access. Google Play health policy
   requires a page rather than a PDF. Then fill both policy fields and in-app
   destinations.
2. **Support:** confirm the configured feedback mailbox or an owner-chosen
   alternative. Publish a project-controlled public support page with actual
   contact details/app help, test anonymously, then use its exact URL for Apple
   and monitored email for Google Play. Do not guess a new contact.
3. **Device acceptance:** select an exact package/hash, configuration and enabled
   scope. Record device/OS, tester/date and results for save/reopen/restart,
   offline local flows, guided-writing cleanup, Safe Mode/lifecycle/mic-off,
   cloud approval/cancellation and relevant export/wipe controls. Evaluate actual
   AI responses. Windows checks do not satisfy Android/iOS acceptance.
4. **Store preparation:** validate signed Android store and iOS packages before
   testing distribution. Capture real platform screenshots and the missing
   Play feature graphic. Complete accurate privacy/data-safety, health, access
   and rating declarations plus provider prerequisites/costs. Use TestFlight
   for Apple beta; do not promise beta access in exchange for financial support.
   Obtain separate store-submission authorization.

Consistency follow-ups: [HelpScreen](../lib/screens/help_screen.dart) repeats
community/seamless-sync claims; [Architecture](Architecture.md) labels keyword
interpretation/fixed prompts as AI. They are not independent evidence. This
three-document change leaves app behavior and legal text for separate review;
reconcile them before publication.

Privacy/support follow-up prepared on 2026-10-14:
[revised policy](PrivacyPolicy.md), [support source](Support.md) and
[publication review](PRIVACY_SUPPORT_PUBLICATION_REVIEW.md). This new work is
separate from the original three-document listing audit. The homepage now has
cookie-free HTTP 200 evidence; policy/support URLs and monitored public contact
remain unverified. Store URL fields remain unset.

## Platform references and validation

Official references checked: Apple [app fields](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information),
[version fields](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information),
[App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy),
[review guidelines](https://developer.apple.com/app-store/review/guidelines/);
Google Play [listing setup](https://support.google.com/googleplay/android-developer/answer/9859152),
[User Data](https://support.google.com/googleplay/android-developer/answer/10144311),
[Health Content and Services](https://support.google.com/googleplay/android-developer/answer/16679511).

Verified customer-field lengths:

| Platform | Field | Length / limit |
| --- | --- | --- |
| Apple | Name | 18 / 30 characters |
| Apple | Subtitle | 28 / 30 characters |
| Apple | Promotional text | 144 / 170 characters |
| Apple | Description | 1,190 / 4,000 characters |
| Apple | Keywords | 72 / 100 bytes |
| Google Play | App name | 18 / 30 characters |
| Google Play | Short description | 73 / 80 characters |
| Google Play | Full description | 1,594 / 4,000 characters |

Checks for this documentation change: field/keyword lengths, relative links
against the full source tree, customer-copy placeholder exclusions, whitespace
and three-file scope. No new application tests or device trials were run; no
store console or public site was changed.

