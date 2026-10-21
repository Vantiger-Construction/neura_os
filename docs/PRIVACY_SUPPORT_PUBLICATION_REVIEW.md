# Privacy and support publication review

**Reviewed:** 2026-10-14. **Source:** Neura `2a0dee11d775f692503b6ee557e219d09298b8ac`
(merged PR #132). This is a review record, not store submission or approval.

## Prepared changes

The existing [PrivacyPolicy.md](PrivacyPolicy.md) is reconciled with implementation.
[Support.md](Support.md) supplies concrete guidance using actual Settings, journal,
provider, sync and Data Controls labels. The in-app privacy summary removes
the future-only cloud claim, universal local-only implication and unverified
support domain. The old Terms draft remains unpublished and is not a new legal
commitment.

## Evidence and limits

| Topic | Inspected source | Conclusion reflected in the drafts |
| --- | --- | --- |
| Local journal | [LocalJournalStore](../lib/services/local_journal_store.dart), [JournalEntry](../lib/models/journal_entry.dart), [Journal Prompt](../lib/screens/journal_prompt_screen.dart), [Voice Journal](../lib/screens/voice_journal_screen.dart) | Local JSON-backed preferences; local save is separate from sync. New prompt IDs may be sync-eligible. Saved transcripts do not prove offline speech processing. |
| Account and sync | [configuration](../lib/config/supabase_config.dart), [AuthService](../lib/services/auth_service.dart), [SyncService](../lib/services/sync_service.dart), [Settings](../lib/src/modules/settings/settings.dart), [Sync Status](../lib/screens/sync_status_screen.dart) | Build configuration, initialized client, account, connectivity and Safe Mode gates. Manual sync exposes status and transfers eligible journal content/metadata. No verified seamless continuity. Profile has no cloud-account deletion control. |
| Cloud AI | [AI service](../lib/services/neura_ai_service.dart), [router](../lib/services/neura_model_router.dart), [stream transport](../lib/services/neura_model_stream.dart), [transaction](../lib/services/neura_cloud_transaction.dart) | OpenAI/Anthropic requests need fresh provider/payload-bound approval, including retry/fallback. Default/background caller without visible approval is denied. No universal provider-retention guarantee. |
| Speech/recording | [VoiceJournalService](../lib/services/voice_journal_service.dart), [native bridge](../lib/services/neura_speech_to_text_service.dart), [ambient service](../lib/services/ambient_listening_service.dart), [sleep service](../lib/services/sleep_listener_service.dart), [privacy controls](../lib/src/modules/privacy/privacy_home_screen.dart) | OS speech may use external processing. Ambient/wake are separate opt-in controls. Encrypted ambient audio does not establish encryption of sleep recordings or all voice data. Physical-device microphone/Safe Mode acceptance remains required; the sleep service alone does not demonstrate a Safe Mode gate. |
| Encryption | [MemoryCrypto](../lib/core/memory/memory_crypto.dart), [memory graph](../lib/core/memory/memory_graph_service.dart), [Legacy Vault](../lib/src/modules/legacy/legacy_vault_service.dart), [provider credentials](../lib/services/neura_model_credentials.dart) | Payload/key protections are scoped. Legacy attachment files and decrypted exports are not universally encrypted. Legacy key migration is conditional on verified secure write. |
| Deletion | [wipe service](../lib/src/core/data_wipe_service.dart), [Data Controls](../lib/src/modules/privacy/data_controls_screen.dart), [auth](../lib/services/auth_service.dart) | Attempts known local stores, credentials/keys and recording/log/export files; reports incomplete deletion. Local sign-out and wipe do not delete cloud accounts/server records, external copies or backups. PR #133's additional tests are separate, unmerged work. |
| Diagnostics/updates/payment | [AppLog](../lib/modules/core/app_log_io.dart), [bootstrap log](../lib/startup/neura_bootstrap_log_io.dart), [LLM counters](../lib/services/neura_llm_diagnostics.dart), [update checks](../lib/services/update_check_service.dart), [purchase function](../supabase/functions/verify-purchase/index.ts) | Local logs/counters, configured manifest checks and payment-related code are distinct. No remote analytics service or analytics opt-out established; no verified live subscription implied. |
| Feedback | [FeedbackScreen](../lib/modules/feedback/feedback_screen.dart) | Existing composer targets `stevenvantiger1@gmail.com` and adds OS/platform information. Sending requires the user/mail client; no test email was sent. |

## Publishing destination

Connected Sites inspection confirms existing project
`appgprj_6acabc2f544c81918e3b2957facd9415`, title Neura Companion OS,
public audience, current user's owner role and live website
[neura-companion-os.justtick8.chatgpt.site](https://neura-companion-os.justtick8.chatgpt.site).

A cookie-free HTTP GET of the homepage on 2026-10-14 returned HTTP 200 and the
actual project HTML without a sign-in page. This verifies the homepage only;
it does **not** verify privacy or support routes.

Separate privacy/support route source has been prepared at the existing Site.
It uses the existing public HTML response helper, with no new intake form,
tracker, account API or database changes. Investor and tester-registration
content, private inbox access and stored submissions are untouched. Source
checks include links/metadata and the existing synthetic intake/privacy tests.

## Contact status

| Detail | Evidence | Remaining requirement |
| --- | --- | --- |
| Existing feedback email: `stevenvantiger1@gmail.com` | App composer and connected site's owner identity use the same address. | Confirm that it is monitored and suitable for public support/privacy requests. Ownership/configuration alone does not establish monitoring. |
| Steven Carl Vantiger | Connected public-site owner identity. | Confirm the actual developer/data-controller name; do not assume an individual's account name is the legal operator. |
| `privacy@neura.com`, `support@neura.com`, `support@neura.app` | Conflicting legacy draft references only. | Not verified; removed from operative candidate contact instructions. No replacement mailbox invented. |

Personal-context retrieval found no explicit earlier controller/contact decision.
A subsequent mailbox-verification request was interrupted; it provided no mailbox
verification evidence. No email, tester submission or private inbox content was
used or published.

## Required next steps

1. Confirm the actual developer/controller name and monitored privacy/support
   email. Replace review-only contact paragraphs with these verified details.
2. Apply the policy to the selected distribution's real enabled services.
   Cloud-enabled distribution requires actual processor/configuration,
   account/server-data deletion handling and retention/backups to be established.
   Resolve age/child-use and any payment-service disclosures for that distribution;
   the website's adult-intake checkbox is not an app age policy.
3. Verify the selected build's in-app disclosure/consent and microphone behavior,
   including any separately enabled recording feature. The policy cannot create
   a missing runtime consent or deletion control.
4. Build and publish the completed separate pages under the existing public Site,
   then request **each exact URL without cookies/authentication/bypass tokens**.
   Confirm HTTP success and expected policy/support content, readable HTML,
   correct contact links and no sign-in wall. A deployment success alone does
   not prove anonymous page accessibility.
5. Only after step 4, assign the working policy URL in both store drafts and the
   support URL in the Apple draft, and add working in-app external links.
   Update this record with saved Site version, source commit and verification.
   Until then the URL fields remain unset.

No production site deployment, application-store submission, automatic merge,
test email or real user-data deletion was performed by this change.

Validation completed: production Site build includes both separate routes;
all six-page metadata/internal-link/asset checks and existing synthetic intake
tests pass. Repository relative links, whitespace, review dates and unset URL
fields pass. Browser layout and anonymous access to the new routes remain
unverified because the pages are deliberately unpublished pending contact
details. No Flutter behavior changed; no new application tests were run.

## Official references

Google Play [User Data](https://support.google.com/googleplay/android-developer/answer/10144311)
requires an accessible privacy policy with developer/contact, collection/sharing,
security, retention and deletion details. Apple
[App Review Guidelines 5.1.1](https://developer.apple.com/app-store/review/guidelines/)
requires accessible privacy information, accurate data handling and applicable
consent/account-deletion controls. These references guide review; they do not
establish legal compliance or store readiness.

Provider references checked: [OpenAI API data controls](https://developers.openai.com/api/docs/guides/your-data),
[Anthropic privacy](https://www.anthropic.com/legal/privacy),
[Supabase privacy](https://supabase.com/privacy),
[Cloudflare privacy](https://www.cloudflare.com/privacypolicy/).
Provider privacy pages do not alone verify a deployed processor agreement or
a particular Neura build's retention/region settings.
