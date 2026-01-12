# Android AAB-only Pipeline + Play Console Track Notes

This provides:
- GitHub Actions workflow to build **signed AAB only**
- Notes for Play Console Internal / Closed / Production tracks
- Release management best practices for a calm v1 launch

## Requirements
- Android keystore (.jks) for signing
- Google Play Developer API service account JSON (for upload automation) OR manual upload

## Secrets you must add to GitHub (Repository → Settings → Secrets and variables → Actions)
- ANDROID_KEYSTORE_BASE64   (base64 of your .jks)
- ANDROID_KEYSTORE_PASSWORD
- ANDROID_KEY_ALIAS
- ANDROID_KEY_PASSWORD
- PLAY_SERVICE_ACCOUNT_JSON (optional, base64 JSON for upload automation)
- PLAY_PACKAGE_NAME         (e.g. com.vantiger.neura.companion)

## Track strategy (recommended)
1) Internal testing (fastest review, limited testers)
2) Closed testing (wider)
3) Production staged rollout (10% → 50% → 100%)

## Play Console notes
- Use **App Bundle** (.aab) for Play Store (preferred)
- Keep `versionCode` increasing every release
- Keep `applicationId` stable forever
- Do not change signing key after first production release

## Release notes tone (Neura style)
Avoid hype. Use calm, factual notes:
- "Pacing improvements"
- "Stability updates"
- "Memory refinements"
