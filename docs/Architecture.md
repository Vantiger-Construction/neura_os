# Architecture Overview

This document outlines the high-level architecture of Neura Companion, a
Windows-first Flutter desktop app distributed as a raw exe via GitHub
Releases (not an app store). Current for the app as of Aug 2026 — earlier
versions of this doc described a Firebase/Firestore-based design that was
migrated away from and never actually shipped; see `lib/` for ground truth
if this drifts again.

## Modules

1. **Authentication & Profiles**
   - Supabase Auth (`lib/services/auth_service.dart`), gated off by default
     for this beta — `SupabaseConfig` ships with placeholder keys, so the
     app boots straight to the dashboard with no sign-in and all data
     on-device. Flip on by supplying real keys in
     `lib/config/supabase_config.dart`.

2. **Security & Compliance**
   - `local_auth` biometric gating exists (`lib/widgets/auth_guard.dart`)
     but is not currently wired into any navigation path — defined, unused.
   - `flutter_secure_storage` / `cryptography` for local data-at-rest.

3. **Ritual & Usage Analytics**
   - Hive local storage
   - CSV & PDF export (`csv_export_service`, `pdf_report_service`)
   - Charts via `fl_chart` (weekly snapshot mood trends)

4. **Dream & Sleep Features**
   - Audio recording, transcription
   - AI-driven dream interpretation
   - Calendar & visualizer UI

5. **Voice & Journaling**
   - Native Windows speech-to-text (`windows/runner/neura_speech_recognizer.*`,
     hand-written WinRT bridge — the `speech_to_text` plugin has no Windows
     implementation upstream)
   - AI-driven prompts & reflections

6. **Offline Mode & Sync**
   - Connectivity detection (`lib/services/sync_service.dart`)
   - Two-way sync with Supabase, conflict resolution — inert while Supabase
     stays unconfigured (see Authentication above)

7. **AI Companion & Mascot**
   - Real LLM chat (Anthropic API, streamed) with spoken replies
     (`lib/services/neura_ai_service.dart`, `neura_tts_service.dart`)
   - Avatar runs in its own always-on-top native window
     (`lib/mascot/`, via `window_manager_plus`), not an in-app overlay

8. **Monetization & Billing**
   - Windows-native path: Stripe Checkout opened in the system browser +
     a stateless Supabase Edge Function to verify payment, redeemed via a
     paste-a-code flow (`lib/services/windows_license_service.dart`)
   - `in_app_purchase`/`BillingService` also present for a future
     Android/Play Billing path, gated behind `kIapEnabled`

9. **CI/CD & Deployment**
   - GitHub Actions build/validate pipeline
   - Desktop installer scripts, SHA-256 checksums per release
