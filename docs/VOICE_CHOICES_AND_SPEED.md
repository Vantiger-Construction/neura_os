# Voice choices, accents and speaking speed

Open **Settings → Neura's Voice**. Existing voice-settings links in chat open the same screen.

- **Speaking speed** has a continuous slider and **Slower**, **Normal**, and **Faster** presets.
- **Voice and accent** lists the installed local English voices. Browse an **Accent**, then explicitly choose a voice. Browsing does not change the selected voice.
- **Play a sample** lets you hear the existing fictional sample sentence without saving that preview voice. **Stop sample** ends it and restores the selected voice.
- **Refresh voices** enumerates the device's current installed voices again.

The accent picker displays only variants actually available in that catalog. Friendly labels cover American, British, Australian, Canadian, Indian, Irish, New Zealand, South African and Singaporean English. Other English variants retain their reported locale. These are descriptions of installed voice locales, not synthesized accent transformations or promised bundled voices.

Windows continues to use Neura's owned local SAPI adapter. Android picker entries must explicitly report no network requirement and must not carry the notInstalled feature. Entries with unknown network requirements, network voices and missing voice data are excluded. There is no new provider, cloud fallback, voice installer, model download, microphone startup or change to startup-listening consent.

## Selection and speed

Voice identity includes both name and locale. Same-named voices in different accents remain separate choices; both values are persisted in the existing device preferences. Android's startup voice preparation preserves the selected locale as well as its name. Native rejection or cancellation does not publish a new selection.

Existing rate bounds remain 0.25–0.75 in the platform adapter's units. Presets use 0.35, 0.5 and 0.65. These are not calibrated multiples of words per minute. Speed applies to the next sample/reply, and actual pace varies by voice.

The existing **Match my mood** control can make a small rate/pitch adjustment around the chosen base settings for replies. Turn it off for a steady pace. Samples use the saved base settings.

## Lifecycle and accessibility

Samples stop on leaving the screen, backgrounding and Safe Mode. Foreground return does not replay audio. If backgrounding interrupted a preview voice, returning restores the selected voice configuration without speaking. Samples and voice selection are disabled while a restart is required.

The selected-voice summary is independent of the accent browsing filter. A rejected native choice retains the previous summary and shows feedback. The layout scrolls at compact sizes and enlarged text. Voice samples have labelled controls and an explicit stop button.

## Validation and physical acceptance

Synthetic tests cover accent labels, malformed/duplicate catalog rows, Android local-only filtering, same-named voice persistence and startup restoration, rejected/late selections, saved speed, Safe Mode, accent browsing, speed presets, sample restoration, backgrounding, restart-required suppression and compact 360-pixel layout at 2× text.

These fixtures do not establish naturalness, actual pronunciation, native voice inventory, loudness, responsiveness or device compatibility. Windows laptop and Samsung SM-S366V / Android 16 listening acceptance remain unmeasured.

On each device, use fictional text and check:

1. Open the voice screen, inspect the actual catalog and choose two available voices or accents.
2. Preview each choice at Slower, Normal and Faster; check that the voice and rate actually change.
3. Select one voice and speed, restart normally, and verify both are retained.
4. Preview a different voice, stop it, and verify the saved voice returns.
5. Background during a sample and return: no replay; the selected voice is restored.
6. Verify Safe Mode/restart-required suppression, keyboard/screen-reader access and compact enlarged-text layout.
7. If only one local voice exists, record that limitation. Additional voice packages are a separate device setup action; Neura does not install them automatically.

Do not change the installed application or device speech settings merely to claim that these checks passed.

