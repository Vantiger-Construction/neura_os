# Explicit local personality profiles (first version)

This is an opt-in, restricted **text-chat workspace**, built on the existing
persona prompt and Flutter motion implementation. It is not a set of accounts
or a claim that Neura can authenticate different people sharing an OS login.

## Try it

1. Open Settings → Neura's Personas → shared tone controls → Your Neura.
2. Choose **Set up separate local profiles** and review the workspace limits.
3. Enable the workspace, add up to eight uniquely labelled profiles, and choose
   a starting style and age group for each. No existing installation style or
   permission is copied. Select a profile explicitly before chatting.
4. Use **Your Neura** to edit that profile's warmth, directness, humor, energy
   and depth. A draft applies only after a verified save. You can select another
   preset or edit the controls again to reverse a change.
5. **End chat and switch profile** clears the session. Choose the next profile.
   Backgrounding, Safe Mode, recovery and restart also require fresh selection.
6. Remove a profile from the selector to delete its saved delivery preferences.
   Recreating the same label creates a new random identifier.

**Enabling is a significant, explicit choice.** The normal installation's
journals, mood/history, vault, reference shelf, plans, tools, room navigation,
voice controls, startup greeting and companion-memory surfaces are excluded.
Existing installation data is retained, not imported or deleted. There is no
return-to-installation control: independently protected identity boundaries
have not been established. Returning to the normal installation currently
requires an explicitly confirmed full local-data wipe and a restart. Do not
enable this workspace on a valued installation until that tradeoff is acceptable.
Removing the last profile leaves an empty selector; it never restores access
to installation-wide private data.

Local Ollama is selected by default and uses the existing explicitly configured,
bounded Windows adapter. No model is downloaded or started by selection. On a
platform without that adapter, local replies remain unavailable. A person may
explicitly select the already-configured installation cloud route: every exact
request, retry or fallback still requires a fresh visible approval. Provider
credentials and the installation's stricter safety policy are not separate
per-person accounts; their existence never supplies request approval. There
is no automatic cloud fallback from local mode. The new workspace has no
microphone or speech-output controls and inherits no voice opt-in.

## Storage and authority

| Boundary | Implemented behavior |
| --- | --- |
| Preferences | Label, random ID, age group and five explicitly chosen style values; no learned traits, transcripts or inferred facts |
| At rest | AES-GCM through `MemoryCrypto`; requires the verified OS-backed installation key; plaintext fallback is refused |
| Selection | Kept only in RAM; never restored automatically after restart |
| Switch | Synchronous epoch revocation, input/history/context removal, generation cancellation and approval-route dismissal; shutdown barrier before activation |
| Audio | Local recognition, legacy recognition, live journal/sleep recorders and voice-pack producers are stopped/drained; profile mode denies restarting capture |
| Private data | Companion-memory owners reject every grant/use while profile mode is enabled, including prior permissions and delayed local-owner loads |
| Prompt | Current selected delivery values and age framing; no installation mood, focus history, companion notes, documents, images or tools |
| Persistence | Serialized writes; encryption followed by platform save and reload/readback verification before publishing state |
| Failed save | No activation from an unconfirmed write; lock and reload durable state. A backend that wrote but reported failure is recovered by reading what actually survived |
| Corrupt/missing registry | Locked error; never replace it with a neutral or installation profile. Existing valid data is not overwritten |
| Removal | Serialized re-encryption of remaining profiles; other styles retained; removed identifiers cannot be selected |
| Full wipe | Revoke first, drain all admitted profile writes, then central verified preferences and device-key deletion; old service handles remain unusable |

The encrypted registry uses `neura.local_profiles.encrypted.v1`, with a
`neura.local_profiles.enabled.v1` sentinel. Either key keeps the workspace
gate closed to installation navigation. The verified empty ciphertext is
written before the sentinel so a rejected first write can be retried safely.
A stalled storage operation must drain before wipe can finish; a hung write is
not a successful wipe. A shared registry with one installation key is **not**
independent cryptographic separation among people. No shared persistent memory
is exposed as a substitute for that missing protection.

The app removes the legacy Navigator when enabling the workspace, rather than
leaving private routes mounted behind its selector. Its own Navigator contains
only the selector/chat and style editor. The floating mascot stays disabled
for this process because the secondary engine does not own a selected profile.
The in-app expressive face and motion continue to use the selected style;
installation mood events do not change its presentation.

## Reproducible validation

Synthetic fixtures use Alex (Calm companion) and Blair (Playful spark), a fake
OS credential store, fake durable preferences, fake native Ollama messages and
a deterministic cloud transport. No real prompts, keys, recordings or journals
are used. They verify:

- Distinct real prompt-builder inputs and live motion parameters, and distinct
  deterministic transport responses to the same question. The fake transport
  proves routing and isolation, not generative quality.
- Retained styles, unselected restart, stale editor rejection, foreground and
  Safe Mode/recovery revocation, rejected shutdown, encrypted storage and removal.
- Failed and misreported saves, corrupt/missing registry, and delayed admitted
  writes racing wipe without subsequent resurrection.
- Actual chat UI transcript removal, legacy-view unmounting, disappearance of an
  open cloud approval at a boundary, no tool advertisement, no stored mood or
  companion note in prompts, and no inherited microphone access.
- Fresh cloud approval for each request; declined approval sends nothing.
- The central full-local-data-wipe path removes registry ciphertext and the
  mocked OS-backed key, and rejects use through old profile handles.

Run with the repository's pinned Flutter version:

```sh
flutter pub get --enforce-lockfile
flutter test --no-pub test/profiles --reporter expanded
flutter analyze --fatal-infos
flutter test --no-pub --concurrency 2 --timeout 2m
python3 tools/test_avatar_source_composition.py
python3 -m unittest discover -s tools/security -p 'test_*.py' -v
git diff --check
```

## Deliberately unfinished

No account/password/PIN authentication, independent per-person keys, isolated
journals/vaults/credentials, persistent profile memory, automatic learning,
profile sync/pairing, profile voice sessions or identity guarantees are claimed.
Anyone with access to this OS application can select, edit or remove a style
profile. Use separate OS accounts/installations when actual human identity
separation is required. Per-profile memory remains blocked until independent
storage, authorization, removal and key lifecycle boundaries are designed and
reviewed together.

Windows/Samsung installation, OS credential availability and migration,
background/resume behavior, native stop acknowledgements, physical microphone
shutdown, actual Ollama response quality and avatar appearance still require
physical-device acceptance with synthetic content. The Flutter fixtures and
successful packaging do not establish those results. No native source,
dependency, model admission threshold or release artifact is changed here.
