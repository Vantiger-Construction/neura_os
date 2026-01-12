# Neura Companion — Store Submission Build Checklist (Public v1)

## 0) Freeze
- [ ] Tag source: `v1.0.0`
- [ ] Feature freeze (no new UX)
- [ ] Only allow bugfixes / stability

## 1) Build Environment
- [ ] Flutter stable pinned (document version)
- [ ] `flutter doctor -v` clean (save output)
- [ ] Android keystore configured (release signing)
- [ ] iOS/macOS: Xcode version noted
- [ ] Windows: Visual Studio Build Tools installed

## 2) Code Quality Gate
- [ ] `flutter clean`
- [ ] `flutter pub get`
- [ ] `flutter analyze` (0 issues)
- [ ] `flutter test` (all green)

## 3) Release Builds
### Android (Play Store)
- [ ] `flutter build appbundle --release` (preferred for Play)
- [ ] Verify AAB installs via internal track
- [ ] Verify permissions match declared features
- [ ] Confirm privacy screens reachable

### iOS (App Store)
- [ ] `flutter build ipa --release`
- [ ] TestFlight upload
- [ ] Verify screenshots + metadata

### Windows (optional distribution)
- [ ] `flutter build windows --release`
- [ ] Smoke test on clean machine/user profile

### macOS (optional distribution)
- [ ] `flutter build macos --release`
- [ ] Notarization plan (if distributing outside TestFlight)

## 4) Store Assets
- [ ] 6 screenshots cropped per platform
- [ ] Short description checked for length
- [ ] Full description no medical claims
- [ ] Privacy Policy URL valid
- [ ] Support email set
- [ ] App icon meets specs

## 5) Privacy + Trust
- [ ] "Delete all data" works (confirmed)
- [ ] Data export (if any) is user-initiated only
- [ ] No hidden tracking
- [ ] Disclaimer present: not medical advice

## 6) Final Smoke Tests (Public v1)
- [ ] First-launch flow
- [ ] Voice on/off toggle
- [ ] Background/idle stability
- [ ] Memory view opens/scrolls
- [ ] Legacy suggestion appears only rarely (assisted)

## 7) Submit
- [ ] Internal testing track first
- [ ] Closed testing track next
- [ ] Rollout staged (e.g., 10% → 50% → 100%)
