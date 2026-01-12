# Neura Companion

**Neura Companion** is an AI-driven wellness and productivity app offering:

- Ritual & Usage Analytics  
- Social & Community Feed  
- Dream Journal & Sleep Analysis  
- Voice & Text Journaling  
- Offline Mode & Sync  
- AI Companion Mascots (Neura & Neuro)  
- In-App Monetization & Billing  
- Full CI/CD & Deployment Pipeline  

## Getting Started

1. **Clone the repository**  
   ```bash
   git clone <repo_url>
   cd NeuraCompanionProject
   ```
2. **Install dependencies**  
   ```bash
   flutter pub get
   ```
3. **Run on device/emulator**  
   ```bash
   flutter run
   ```
4. **Run tests**  
   ```bash
   flutter test
   ```

## Folder Structure

- `lib/models/` – Data models  
- `lib/services/` – Business logic & API wrappers  
- `lib/screens/` – UI screens  
- `lib/widgets/` – Reusable widgets  
- `docs/` – Policies, guides, architecture docs  
- `.github/workflows/` – CI/CD configs  
- `scripts/` – Deployment scripts  

## Contributing

Please follow coding standards and update tests accordingly.

## Upgrade Pack v5 (Navigation + Neura Chat + Diagnostics)
- Added `EnhancedNavigation` (bottom tabs + global Neura FAB)
- Added local `NeuraAICore` for offline-first chat
- Added `Diagnostics` with persistent NDJSON logs
- Added global error handler (logs uncaught Flutter + platform errors)

## Upgrade Pack v6 (Mood + Voice Journal + Web-safe Logging)
- Added Mood Check-In + Mood History (SharedPreferences persistence)
- Wired Voice Journal to on-device Speech-to-Text (`speech_to_text`)
- Split AppLog into IO + Web implementations (conditional export) so Flutter Web builds don’t choke on `dart:io`
- Dashboard tiles updated to include mood + voice journal

### Platform notes
- **Microphone permission** is required for Speech-to-Text.
  - Android: ensure `RECORD_AUDIO` permission is present (and request at runtime).
  - iOS: add `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` in `Info.plist`.
