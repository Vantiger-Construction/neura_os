class PrivacyTexts {
  static const privacyPolicy = '''
# Privacy Policy Summary

Last reviewed: October 14, 2026. Development policy; public contact details are still being verified.

## Local information
Neura saves journal text, mood check-ins, preferences and other module records on this device. Journals use app preferences; they are not all encrypted by Neura. Encrypted memory and selected ambient clips use separate encryption. Legacy Vault body encryption does not automatically encrypt attachment files or decrypted exports.

## Optional cloud AI
Configured cloud chat uses OpenAI or Anthropic. Review the provider, conversation history, images and permitted context before approving each outbound attempt. Retries and fallback need fresh approval. Cancelling cannot retrieve information already sent. Provider retention and processing depend on the applicable service and account settings.

## Account and synchronization
Configured account and journal-sync services use Supabase; they are already implemented. Manual sync requires an available backend, sign-in and connectivity. It can upload eligible saved journal content and metadata, including new prompt entries. Cloud-chat approval is separate from sync. Local saving does not itself establish an upload, automatic backup or seamless cross-device handoff.

## Microphone and speech
Voice features require relevant device permissions. Platform speech recognition or speech output may use network services; a locally saved transcript does not prove local-only audio processing. Optional ambient recording and wake-phrase listening are off by default. Safe Mode keeps the supported speech, ambient and wake-phrase paths off and blocks cloud chat/account sync.

## Export and deletion
Open Settings > Privacy & Safety > Data Controls for Legacy Vault export/import, local Vault deletion or Wipe ALL local data. Review export contents and the wipe result. Restart Neura after a wipe, or before retrying an incomplete wipe. Copies in OS backups, files moved elsewhere, shared exports and provider/server records are separate. Local wipe signs out this device; it does not delete a cloud account or server journal records.

## Feedback and privacy contact
Settings > Send Feedback opens your email app using the existing project feedback destination and includes platform/OS information. Review it before sending. Do not send credentials, private writing or recordings. A monitored public privacy/support contact is being verified before policy publication.

The project website intake is separate from app data. Its private submission-removal link does not wipe the app.
''';

  static const termsOfService = '''
# Terms of Service (Short Draft)

By using Neura Companion / Neura OS, you agree that:

- The app provides general information and coaching prompts and is **not medical, legal, or financial advice**.
- You are responsible for how you use the app and for any data you choose to export or share.
- The app is provided "as is" without warranties.

If you are in immediate danger or considering self-harm, contact local emergency services or a crisis hotline in your region.
''';

  static const disclaimer = '''
# Safety Disclaimer

Neura Companion / Neura OS can be supportive and reflective, but it is not a substitute for a licensed professional.

If you feel unsafe, overwhelmed, or at risk of harming yourself or others, seek immediate help from local emergency services or a qualified professional.
''';
}

