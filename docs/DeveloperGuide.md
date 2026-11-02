# Developer Guide

## Prerequisites

- Flutter SDK 3.47.9 (includes Dart 3.13.7)
- Rust 1.99.1 (see `rust-toolchain.toml`)
- Firebase CLI (for hosting)  
- Appropriate API keys/secrets in environment variables or secure storage  

See [the November dependency refresh](DEPENDENCY_REFRESH_2026_11.md) for
platform minimums, pinned tooling, and storage migration constraints.

## Setup

1. **Environment configuration**  
   - Copy `.env.example` to `.env` and fill environment variables (Firebase token, Stripe keys).  

2. **Generating Freezed models**
   ```bash
   dart run build_runner build
   ```

3. **Running the application**  
   ```bash
   flutter run
   ```

4. **Testing**  
   ```bash
   flutter test
   ```

5. **CI/CD**  
   - Push to `main` branch triggers GitHub Action  
   - Set `FIREBASE_TOKEN` in repo secrets  

6. **Deploy**  
   ```bash
   scripts/deploy_firebase.sh
   ```

7. **Building installers**  
   ```bash
   scripts/build_installer.bat
   ```

## Code Style

- Use strong types and immutable models  
- Add unit tests and widget tests under `test/`  
- Adhere to `analysis_options.yaml` lint rules
