# Neura Companion OS Privacy Policy

**Prepared and last reviewed: October 14, 2026**

> Review draft, not an effective published policy. The developer/data-controller
> name and monitored privacy/support contact must be confirmed before publication.
> This draft updates the existing repository policy. It describes the inspected
> development implementation, not an app-store-approved release.

## Introduction

Neura Companion OS is companion software for everyday questions, reflection and
personal notes. This policy explains the information the app handles, where it
can be stored or sent, and the controls available to you. Features differ between
development builds and platforms. Local storage, cloud AI, account services and
website registration are separate activities.

Neura supplies general information and reflection tools. It does not provide
medical treatment or emergency monitoring. Personal writing and recordings may
contain sensitive information; share only what you intend to disclose.

## Information handled by the app

| Information | Purpose and handling |
| --- | --- |
| Journal and dream text; mood ratings and notes; memory, activities and other records you create | Save and display your writing, check-ins, history and selected companion context. Saved journal entries are held locally as JSON in app preferences. |
| Settings and preferences | Remember choices such as appearance, voice, notifications, room and privacy controls. |
| Conversation text and selected images or context | Produce replies using the selected local or approved cloud provider. Relevant conversation history and permitted context can accompany a request. |
| Microphone input, speech transcripts and recordings | Supply the voice or recording feature you enable. Speech recognition and raw-audio recording have different processing and storage behavior. |
| Legacy Vault capsules, attachments and exports | Save, import or share material you choose. Capsule-body encryption does not automatically encrypt attachment files or all export contents. |
| Account email, password, display name and session information, when account services are configured and used | Sign in, reset a password, update your profile and associate synchronized journal records with your account. |
| Local usage, diagnostic and reliability records | Display history, diagnose failures and support recovery. These can include event times, error classifications and technical information. |

The draft's earlier claim of a general analytics opt-out is removed. The inspected
app uses local history, counters and logs; a remote analytics collection service
or universal analytics toggle has not been established.

## Local storage and security boundaries

Saved journals and many preferences and module records use app preferences or
local files. They are **not all encrypted by Neura**. Access also depends on your
device account, operating-system protections and any device backups.

The encrypted memory implementation encrypts record payloads and uses
OS-backed secure storage for new device keys. Older preference-backed keys may
remain until a successful migration. Selected metadata remains outside encrypted
payloads. Optional ambient audio clips are encrypted locally. Legacy Vault
encryption protects selected capsule bodies; attachment files and some exports
can remain readable. Decrypted exports intentionally contain readable material.

The optional device-lock feature asks the operating system to authenticate you;
Neura uses the authentication result rather than collecting your biometric
template. It does not turn all app files into encrypted storage. No security
feature guarantees that a device, backup, recipient or service can never expose
information.

## Optional cloud AI and local conversation

Cloud AI requires a configured provider key and internet access. The supported
chat router targets OpenAI and Anthropic. Before each outbound chat attempt,
Neura presents a provider-bound approval request. Retry or provider fallback
requires a new approval. Cancelling before transmission prevents that attempt;
cancelling after transmission cannot retrieve information already received by a
provider.

An approved request can include your current message, relevant conversation
history, companion instructions, selected context, selected images and applicable
tool-related material. The provider also receives authentication and ordinary
connection/request metadata. Review the preview and avoid sending information
you do not want that provider to process. Approval for cloud chat is not approval
for journal synchronization or operating-system speech processing.

The OpenAI adapter requests that responses not be stored, but that request is
not a promise of zero provider retention. Provider processing, logging, training
choices and retention depend on the applicable API service, account settings and
terms. Neura does not claim to control those practices.

The Windows Offline Ollama path sends conversation text to a separately installed
local Ollama service on loopback. It does not automatically fall through to the
cloud AI router. Ollama/model installation and downloads are separate from that
conversation path; local service availability, permissions and device resources
still matter. This is not a claim that every feature or mobile speech service
works without a network.

## Optional account services and journal synchronization

Account and synchronization code already exists; it is not merely a future
capability. It requires build-time Supabase configuration and an initialized
client. Without that configuration, the account and sync path is unavailable.
Safe Mode prevents the supported cloud-account/sync and cloud-chat paths.

When an available synchronization flow runs while you are signed in and online,
eligible journal content, record identifiers, timestamps, revision times, mood
tags and voice-entry flags can be sent to the configured Supabase backend and
downloaded to this device. New prompt-journal records can be eligible too.
Some legacy local-only records are excluded. Synchronization can consider all
eligible journal entries; it is not limited to one currently visible entry.

Local saves and synchronization are separate operations. Do not assume a save
means an upload, or that synchronization is seamless, automatic or a verified
cross-device backup. The supported Settings > Sync Status screen exposes manual
sync. Cloud-chat approval does not apply to these backend requests. Signing out
or blocking future sync does not erase existing server copies.

A local-data wipe signs out this device and attempts to clear its local session.
It does not delete the Supabase account, server journal records, other devices'
sessions or third-party retention. The inspected Profile screen has no
self-service cloud-account deletion control.

## Speech, recordings and device permissions

Voice features need microphone access and, where applicable, operating-system
speech permission. You can deny or revoke permissions in device settings and
continue with available text features. Safe Mode keeps the supported chat/voice,
ambient and wake-phrase capture paths off.

Voice journaling uses Windows native speech recognition or the platform speech
service. A transcript saved locally does **not** establish that its audio was
processed exclusively on the device. Your operating system, installed speech/TTS
provider, language package and settings may involve network processing.

The optional ambient-clips and wake-phrase controls are off by default and have
separate purposes. Ambient capture listens to microphone input to identify
speech and stores selected encrypted clips with local metadata. An enabled
wake-phrase feature listens/transcribes to detect its phrase. Review those
controls before enabling them; they are not the same as typing a message.

Other recording features can create local audio files, including sleep
recordings. Those files are not covered by a universal audio-encryption promise.
Speech output uses the system's chosen voice service. File/image pickers and
device sharing use the operating system and any destination you select.

## Sharing and third-party processing

Information can leave the device through an approved cloud AI request, configured
account/sync operation, platform speech service, selected export/share,
support email or other enabled integration. A configured update check can contact
a release-manifest host; opening a link contacts its destination.

Applicable providers include OpenAI or Anthropic for cloud AI; Supabase for
configured account/journal services; operating-system and speech providers for
voice; and your chosen mail, sharing, backup or file service. These services may
process connection metadata such as IP address and handle information under their
own applicable terms. Provider locations, backups and retention are not established
by local encryption or request headers.

Payment-related code also exists, including store purchase integrations and a
Supabase function that can verify a Stripe session. This does not establish a live
subscription, checkout or entitlement service. A distributed build enabling such
a service needs a reviewed disclosure of its actual provider and purchase data.

## Retention, export and deletion

Local writing and module records can remain until you delete them. Diagnostic
logs have rotation/bounds; those limits are not a retention schedule for all data.
Exports, backups, mail and copies on other devices have separate lifetimes.

Settings > Privacy & Safety > Data Controls offers Legacy Vault export/import,
deletion of the local Legacy Vault, and Wipe ALL local data. Raw Legacy Vault
exports preserve encrypted capsule bodies; decrypted export needs the relevant
passphrase. Attachment files are copied as files, so do not assume a raw archive
encrypts them.

The full wipe stops known producers/writers and attempts to remove known
app-owned credentials, keys, settings, records, recordings, logs and generated
exports on this device. Check its result. If it reports an incomplete wipe,
restart Neura before retrying and report the failed step without private content.
After a successful wipe, restart Neura before continuing.

Neither a local wipe nor uninstall guarantees secure erasure from storage media,
OS backups, files you moved elsewhere, server backups or copies already shared.
This app's current local wipe is not a cloud-account deletion tool. For cloud
records or account/privacy requests, use the confirmed project contact when
published; the request route and applicable retention must be established for
the selected cloud-enabled distribution.

## Project website and support requests

The project website is separate from the app. Its tester/supporter/investor intake
asks for an email, optional first name/message, interest, device choice and
consent. It stores submissions and a creation time/consent version in a private
Cloudflare-hosted project inbox. Removal tokens are stored as hashes; limited
hashed-email counters help restrict repeat submissions. The form requires an
18-or-older confirmation. This does not establish the app's final age policy.

A private removal link is shown after submission and can delete that submission.
Keep it private. Website submissions are not placed in a public directory or sent
to a conversation model by the intake code. The hosting platform can process
connection/security information and necessary cookies; the inspected page also
receives a Cloudflare security cookie. No project advertising tracker was
identified in the inspected site source.

Send Feedback in Neura opens your email app with your written feedback and
platform/OS information. The mail provider processes what you send. Inspect the
message first. Do not send passwords, API keys, recordings, journal text or other
sensitive material unless you deliberately choose to do so through an appropriate
private channel. Website deletion does not remove app data or mail copies.

## Contact and changes

The repository's existing feedback address is `stevenvantiger1@gmail.com` and it
matches the connected project's owner account. That establishes an existing
project-configured destination, **not** a confirmed monitored privacy mailbox or
legal controller identity. The conflicting `neura.com`/`neura.app` contact
addresses are not verified project contacts.

Before this policy becomes public, the publisher must identify the
developer/data controller, confirm a monitored privacy/support address and
replace this review-only contact paragraph with those verified details. Material
changes to enabled services or data handling require an updated policy and
appropriate in-app disclosures.

Provider references: [OpenAI API data controls](https://developers.openai.com/api/docs/guides/your-data),
[Anthropic privacy](https://www.anthropic.com/legal/privacy),
[Supabase privacy](https://supabase.com/privacy),
[Cloudflare privacy](https://www.cloudflare.com/privacypolicy/).
These references do not replace this policy or establish Neura's legal compliance.

