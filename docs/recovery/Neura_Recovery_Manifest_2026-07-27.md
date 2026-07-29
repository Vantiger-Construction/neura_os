# Neura Recovery Manifest

**Assessment date:** 2026-07-27  
**Scope:** Google Drive Neura archives, installers, setup guides, checksums, build documents, and recovery files compared with the latest contents and history of `Vantiger1/neura_os` on GitHub.  
**Operation mode:** Read-only. No Drive or GitHub content was modified or deleted.

## Executive result

The current app is recoverable from GitHub. The authoritative recovery point is the root Flutter project on branch `Neura` at commit [`33c23a5b96f414590179b8a98b32110a380c7827`](https://github.com/Vantiger1/neura_os/commit/33c23a5b96f414590179b8a98b32110a380c7827), dated 2026-07-15. Its history also retains the 67 legacy ZIP packs removed from the working tree in commit [`5ebef94396c8b7a84e1dd7d46fc494496adf0627`](https://github.com/Vantiger1/neura_os/commit/5ebef94396c8b7a84e1dd7d46fc494496adf0627); they can be recovered from parent commit `3db5dabdb96d2ab02d5c4d3c27b8a8f37df68ce2`.

Google Drive contains useful historical evidence, old source fragments, module ZIPs, setup scripts, and duplicate installer stubs. It does **not** contain a current full build of the July 2026 app. Several Drive items with names such as “Full,” “Complete,” or “All In One” are small 2025-era scaffolds, not complete recovery bases. They should be retained but never overlaid onto the current GitHub root.

The principal gaps are a current Windows release package and installer, Android signing material, a checksum for the current head, deployed Stripe/Supabase configuration, and a verified end-user data backup. The checked-in `NeuraBeta_win64.zip` checksum refers to an older build and the ZIP itself was not found.

## Source-of-truth rules

1. **Current application source:** the root of [`Vantiger1/neura_os`](https://github.com/Vantiger1/neura_os), branch `Neura`, pinned to `33c23a5b96f414590179b8a98b32110a380c7827`.
2. **Deleted legacy packs:** Git history at `3db5dabdb96d2ab02d5c4d3c27b8a8f37df68ce2`, kept outside the reconstructed app.
3. **Historical reference material:** selected Drive archives and folders listed below, quarantined from current source.
4. **Never use as a merge base:** nested repository copies such as `neura_companion_merged/`, `neura_os/`, `Neura_OS_Complete_Merged/`, `Neura_Companion_OS_ALL_IN_ONE_FINAL/`, `temp_project/`, or `neura companion v/...`.
5. **Do not trust names alone:** “complete,” “full,” “final,” and “installer” labels often refer to minimal or partial historical artifacts.

## Deduplicated recovery manifest

| Component | Best source | Backup state | Duplicates or cautions |
|---|---|---:|---|
| Current Flutter app | GitHub branch `Neura`, commit `33c23a5…` | **Recoverable / authoritative** | Use only the root project. Nested project trees are stale copies. |
| Full source history | GitHub repository history | **Recoverable, but single-remote risk** | Create an offline `git bundle --all` immediately after recovery. |
| 67 removed legacy ZIP packs | Git commit `3db5dab…` | **Recoverable from history** | Removed one commit later by `5ebef9…`; history was not rewritten. Eight filename families have numbered duplicates. |
| Current dependency/build definition | Root `pubspec.yaml`, `.metadata`, platform folders | **Recoverable / authoritative** | Flutter stable revision recorded as `f6ff1529fd6d8af5f706051d9251ac9231c83407`; Dart constraint is `>=3.0.0 <4.0.0`. |
| Current Windows build script | GitHub `windows/Install-Neura-Windows.ps1`, `.bat` | **Backed up, but build launcher only** | Not a distributable installer. PowerShell defaults to a sibling project path unless `NEURA_PROJECT_DIR` is set. |
| Windows beta packaging | GitHub [`package_beta.ps1`](https://github.com/Vantiger1/neura_os/blob/Neura/package_beta.ps1) | **Backed up, usable after validation** | Packages `build\windows\x64\runner\Release`; generated README still contains release TODOs. |
| Current installer kit | GitHub `tools/oneclick_installer_kit/` and `tools/distribution_packaging_kit/windows/MSIX/` | **Source backed up; output unverified** | No current `.exe` or `.msix` installer was found. |
| Windows beta binary | Expected `NeuraBeta_win64.zip` | **Missing** | A checksum exists, but the ZIP is absent from the current GitHub tree and was not found in Drive. |
| Checksums | GitHub [`CHECKSUMS_SHA256.txt`](https://github.com/Vantiger1/neura_os/blob/Neura/CHECKSUMS_SHA256.txt) | **Backed up but stale for current head** | Records `NeuraBeta_win64.zip` SHA-256 `2ce799f90ae187d90c02e89df7e240a74a62bc54c368bcdd4d31420825cb62d5`, size `81,985,588`; four later commits materially changed the app. |
| Build/release documents | GitHub `STORE_SUBMISSION_BUILD_CHECKLIST.md`, `FINAL_MERGE_REPORT.md`, `MERGE_MANIFEST.json`, README | **Backed up, mixed currency** | Checklist still has open gates. Architecture and Play Store guidance contain stale Firebase/Gradle assumptions. |
| Windows monetization code | GitHub head: `lib/services/windows_license_service.dart`, `supabase/functions/verify-purchase/index.ts` | **Source backed up** | External Stripe Product/Price/Payment Link, Supabase deployment, and secret were not verified or recovered. |
| Broad 2025 Drive scaffold | [`Neura_Companion_All_Inclusive_Bundle.zip`](https://drive.google.com/file/d/1lhVWkuBv1xvNzJ48acv7Tv0LMqqbwTQT/view?usp=drivesdk) | **Readable historical backup** | 108 files and only 68,143 uncompressed bytes; not the current app. |
| Drive tests variant | [`NeuraCompanion_WithTests.zip`](https://drive.google.com/file/d/17aJ8D7UGM1jTwjq-S1PObdBjhhXjUr2n/view?usp=drivesdk) | **Preserve for unique test variants** | 61 of 63 non-empty file signatures match the All Inclusive bundle. |
| Drive multi-stack scaffold | [`Neura_Companion_Scaffold_AtoZ_Plus_full.zip`](https://drive.google.com/file/d/1nZR0b4mhJm8-CP7Tl3Q3-sSBxAEVlAPl/view?usp=drivesdk) | **Preserve as historical scaffold** | Unity content is a placeholder stub; FastAPI and Node content is also skeletal. |
| Drive Module 1–3 packs | `Neura_Module01_IntegrationKit.zip`, `Neura_Module01_EmotionCore.zip`, `Neura_Module02_VisemeJournalDream.zip`, `Neura_Module02_IntegrationKit.zip`, `Neura_Module03_RoomsAudioOutfits.zip`, `Neura_ProjectSetup_AfterModule3.zip` in [`Neura_MegaMerge`](https://drive.google.com/drive/folders/1QLEg3ruHzNjnBUziY4RZvAAKLOM4jdcY) | **Readable historical fragments** | Very small packs; several audio assets are zero-byte placeholders. Audit manually only after the current app builds. |
| Drive Auth/TTS rollout | [`Neura_Companion_SuperRollout_AuthTTS_1`](https://drive.google.com/drive/folders/1JOXDvYFUNDJRd5kNsE2V61vRLlwoIbYx) | **Readable historical source** | Canonical of two near-identical folders; minimal Auth/TTS Flutter app, not current source. |
| Drive full-stack shell | [`neura_fullwire`](https://drive.google.com/drive/folders/1X7kuWqJcnKnZBEKyZF4gZT5WlpY4ta5E) | **Partial only** | Tiny Flutter shell; backend `main.py` is empty. |
| Drive NSIS installer | [`installer.nsi`](https://drive.google.com/file/d/1laccU_UdKzxizkK5Zcdi5zd5dK5gO3oB/view?usp=drivesdk) | **Readable historical template** | Exact duplicate exists in a second folder; assumes `NeuraCompanion.exe` and a generic `build\*.*` layout. Do not use without updating it for current output. |
| Drive AutoSetup folders | [`Neura_Companion_AutoSetup_FullStack (3)`](https://drive.google.com/drive/folders/1wmk7Hwh6HjOXiBSyLRM1v5LJWk4L9Qc_) | **Only a provenance note** | Three exact duplicate folders, each containing the same one-line generated README. |
| Drive CI-fix scaffold | [`Neura_Scaffold_CI_Fix`](https://drive.google.com/drive/folders/1WVdPZ2XUZ6bKW4RrTf0iE0duPac381O9) | **Readable but obsolete** | Exact duplicate folder exists; script creates a minimal “Neura CI OK” app, not the current app. |
| Unity project/runtime | Git history ZIPs plus nested `Neura_OS_Complete_Merged/world/NeuraWorld` | **Prototype material only** | Current root Unity integration was removed as dead code. No verified finished Unity project with complete scenes, prefabs, `Packages`, and `ProjectSettings` was found. |
| End-user data and exports | No authoritative artifact found | **Unverified / likely missing** | Source recovery does not recover local Hive/preferences, journal, memory, relationship, or user-generated data. |

### What “backed up” means here

“Recoverable” means the item was readable from GitHub or Drive during this assessment. It does not mean there are two independent copies. GitHub history is especially valuable, but it remains a single remote until an offline bundle is made. Drive did not expose a trustworthy checksum manifest for its Neura archives, so Drive integrity is based on successful reads and internal archive inspection rather than a separately stored cryptographic inventory.

## Drive deduplication decisions

The [`Neura_Companion_MegaBundle`](https://drive.google.com/drive/folders/1j3HePXe-945Sye4xcDN7hGJQdOiK7z0b) contains 15 ZIPs. Retain all without deletion, but use only these as canonical historical representatives:

| Canonical historical item | Why retain it | Redundant or largely subsumed variants |
|---|---|---|
| `Neura_Companion_All_Inclusive_Bundle.zip` | Broadest old Flutter/scaffold snapshot | `neuro_companion_merged.zip`, `Neuro_Companion_Final (1).zip`, `neuro_companion_final_beast.zip`, and most of `NeuraCompanion_Final.zip` |
| `NeuraCompanion_WithTests.zip` | Preserves two apparently unique test/source variants | Most content duplicates All Inclusive |
| `Neura_Companion_Scaffold_AtoZ_Plus_full.zip` | Broadest multi-stack scaffold | `Neura_Companion_Scaffold_AtoZ_full.zip` |
| `NeuraCompanion_FullSource.zip` | Compact old Dart-source snapshot | `neura_companion_modules.zip` is fully contained; most of `neura_companion_build.zip` overlaps |
| `NeuraCompanion_CompleteIntegration.zip` | Slightly broader than `NeuraCompanion_Final.zip` | `NeuraCompanion (1).zip` is fully contained in the Final family |
| `neuro_companion_merged.zip` | Contains the Azure variant’s content | `Neuro_Companion_Full_Merged_With_Azure.zip` is fully contained |
| `Neuro_Companion_Developer_Kit.zip` | Standalone brochure provenance | Contains only the brochure PDF |

Additional exact or functional duplicate families:

- `Neura_Companion_AutoSetup_FullStack (2)`, `(3)`, and `(4)`: exact same generated README.
- `Neura_Scaffold_CI_Fix` and `Neura_Scaffold_CI_Fix_1`: same README and BAT.
- `InstallerPackage (1)` and `InstallerPackage (1)_1`: exact same `installer.nsi`.
- `Neura_Companion_SuperRollout_AuthTTS` and `_1`: same key guides and build scripts; `_1` is the later copy.

No deletion is recommended. Deduplication here means choosing one retrieval source, not removing copies.

## Missing, stale, or unverified pieces

### Critical for a reproducible release

- A current Windows release ZIP built from `33c23a5…`.
- A current Windows installer (`.exe` or `.msix`) tested on a clean machine.
- A new SHA-256 manifest tied to the exact source commit and build environment.
- Android release keystore, `key.properties`, aliases, and passwords.
- Stripe Product/Price/Payment Link and the deployed Supabase Edge Function and required secret.
- A captured toolchain manifest: Flutter/Dart version, Visual Studio and Windows SDK versions, Java/Android SDK versions, and package lock state.

### Critical if user data matters

- Local Hive databases, secure-storage material, preferences, journal/memory exports, relationship data, and any imported local-model or media assets.
- A documented restore test showing that a fresh install can re-open the recovered data.

### Historical or design gaps

- A complete, verified Unity project. The Drive Unity scaffold is only a placeholder; GitHub retains prototype material but the current app is Flutter.
- Exact named recent deliverables were not found in Drive or current GitHub under these names: `Neura_v5_0_FirstPlayable`, `Neura_v4_9_DeepAutomation`, `Neura_Complete_OS_Integrated_v3_FULL`, `Neura_Phase16_Embodied_Intelligence_Runtime`, `NeuraCompanion_FULL_MERGED_1_37_COMPLETE`, and `Neura_UltraMerged_Unity_Rust_Viseme_App`.
- `fix_smart_quotes.ps1` exists on GitHub, but no corresponding Drive backup was found.
- `FINISH_LINE_BRIEF`, `LAUNCH_GATES_BRIEF`, `RUN_ALL_PHASES`, `BUILD_ANDROID`, and `WIRING_FLUTTER_TO_RUST` were not found under those exact names.
- README, architecture, and store-submission documentation need reconciliation with the current Supabase/Kotlin-DSL-era project before release.

## Exact rebuild order

The commands below are recovery instructions; they were not executed against Drive or GitHub during this assessment.

### 1. Establish an isolated recovery workspace

Use a healthy disk with enough space for the repository, a full-history bundle, the pre-cleanup archive, and release outputs. Do not copy any Drive bundle into the application tree.

### 2. Clone and pin the authoritative source

```powershell
git clone --branch Neura --single-branch https://github.com/Vantiger1/neura_os.git
Set-Location .\neura_os
git rev-parse HEAD
git switch -c recovery/2026-07-27 33c23a5b96f414590179b8a98b32110a380c7827
git status --short
```

Expected pinned commit: `33c23a5b96f414590179b8a98b32110a380c7827`.

### 3. Make an independent full-history backup

```powershell
git bundle create ..\neura_os_full_history_2026-07-27.bundle --all
git bundle verify ..\neura_os_full_history_2026-07-27.bundle
```

Copy the verified bundle to a second independent storage location.

### 4. Export the pre-cleanup state separately

```powershell
git archive --format=zip `
  --output ..\neura_os_pre_cleanup_3db5dab.zip `
  3db5dabdb96d2ab02d5c4d3c27b8a8f37df68ce2
```

This archive contains the source state immediately before the 67 legacy ZIP packs were removed. Keep it outside `neura_os`. Do not extract it over the current project.

### 5. Quarantine prototype and historical material

If Unity investigation is needed, copy only these into a separate `historical_review` directory:

- `Neura_Unity_Flutter_Bridge.zip`
- `Neura_Unity_World_Core.zip`
- `Neura_OS_Complete_Merged/world/NeuraWorld`
- The three canonical Drive MegaBundle representatives and Module 1–3 packs

Treat all of them as evidence to compare file-by-file, never as a bulk merge.

### 6. Restore the Flutter toolchain

The repository records Flutter stable revision `f6ff1529fd6d8af5f706051d9251ac9231c83407`. If reproducing that exact revision is impractical, use a compatible stable Flutter release and record the substitution.

Install:

- Git
- Flutter with Dart `>=3.0.0 <4.0.0`
- Visual Studio Build Tools with **Desktop development with C++**
- Windows SDK required by Flutter
- Android Studio/SDK and Java only if rebuilding Android

Then run:

```powershell
flutter --version
dart --version
flutter doctor -v
flutter clean
flutter pub get
flutter analyze
flutter test
```

Recent Git history reports clean analysis, 24 passing tests, a successful Windows release build, and live boot. Reproduce all four results locally before packaging.

### 7. Configure external services without committing secrets

For Windows monetization:

1. Recreate or confirm the Stripe Product and Price.
2. Recreate or confirm the Stripe Payment Link.
3. Recreate or confirm the Supabase project.
4. Deploy `supabase/functions/verify-purchase/index.ts`.
5. Set the required Edge Function secret in Supabase.
6. Supply only documented public identifiers to the app; keep service-role and payment secrets outside source control.
7. Test success, cancellation, invalid receipt, offline, and revoked-license paths.

If monetization is not required for the first recovery build, disable or sandbox the external path explicitly and document that choice.

### 8. Build and smoke-test Windows

```powershell
flutter build windows --release
.\build\windows\x64\runner\Release\neuro_companion.exe
```

Smoke-test at minimum:

- First launch and subsequent launch
- Main navigation and dashboard
- Avatar/mascot windows
- Chat, TTS, STT, and microphone denial
- Journal/memory persistence
- Relationships, Guardrails, Joy, One Good Move, Legacy/Care flows
- Offline behavior
- Premium/Windows license screen
- Close, relaunch, upgrade, and uninstall behavior

Do not proceed if the root project only works after copying files from a nested duplicate tree.

### 9. Produce a fresh Windows beta package and checksum

Resolve the TODOs in the generated beta README first, especially the feedback link and any local-model requirement. Then:

```powershell
powershell -ExecutionPolicy Bypass -File .\package_beta.ps1 `
  -RepoRoot "$PWD" `
  -AppVersion "1.0.0-beta"
```

Calculate and record fresh hashes:

```powershell
Get-FileHash .\dist\*.zip -Algorithm SHA256
git rev-parse HEAD
flutter --version
```

Do **not** reuse SHA-256 `2ce799f9…`; it predates four material commits.

### 10. Build a real installer

Only after the raw Release directory and ZIP pass smoke tests:

1. Prefer the current GitHub MSIX/distribution kit.
2. Wire it to the actual `build\windows\x64\runner\Release` output.
3. Set the package identity, publisher, version, upgrade behavior, icons, and signing certificate.
4. Install on a clean Windows profile.
5. Test upgrade, repair, uninstall, shortcuts, data retention, and blocked-network behavior.

The Drive NSIS script is only a reference; its executable name and input layout are stale.

### 11. Rebuild Android separately

After recovering or replacing signing material:

```powershell
flutter clean
flutter pub get
flutter build appbundle --release
Get-FileHash .\build\app\outputs\bundle\release\app-release.aab -Algorithm SHA256
```

Upload first to an internal testing track. Verify signing, install/upgrade, permissions, privacy disclosures, billing configuration, background behavior, and data restore before production submission.

### 12. Freeze the recovered release

Create and verify all of the following:

1. `neura_os_full_history_2026-07-27.bundle`
2. A source archive named with commit `33c23a5…`
3. Windows ZIP and installer
4. Android AAB, if applicable
5. SHA-256 manifest for every artifact
6. Toolchain/environment manifest
7. Secret-free deployment runbook
8. User-data export and restore instructions

Store the set in at least two independent locations. Keep the Git commit, artifact hashes, and build environment together.

### 13. Audit legacy archives last

Only after the pinned current app builds and runs:

1. Unpack one historical archive into a disposable comparison directory.
2. Compare paths and contents against current root.
3. Classify each unique file as obsolete, prototype, documentation-only, test-only, or a candidate feature.
4. Port candidate behavior manually into the current architecture with tests.
5. Never copy a historical `pubspec.yaml`, platform folder, generated file, or entire `lib/` tree over current source.

## Git-history archive inventory

The cleanup commit removed 67 ZIP files representing 58 filename families. These are recoverable from `3db5dab…`; numbered copies should remain deduplicated logically:

- `Neura_AfterStormModule_Pack.zip`
- `Neura_Audience_KidsSafety_Pack.zip`
- `Neura_Audience_Selector_Pack.zip`
- `Neura_CareMode2_TrustedContacts_Playbooks_Pack.zip`
- `Neura_Companion_AllNeuraMerged_NoTODOs_FinalFlow.zip`
- `Neura_Companion_FINAL_LIVING_SYSTEM.zip`
- `Neura_Companion_FullApp_WithOS_v1.zip` — duplicate copy: `(1)`
- `Neura_Companion_FullApp_WithOS_v2_HookedDashboard.zip`
- `Neura_Companion_FullApp_WithOS_v3_MoodThemed.zip`
- `Neura_Companion_FullApp_WithOS_v4_AutoInsights.zip`
- `Neura_Companion_FullApp_WithOS_v5_PersonaTone.zip`
- `Neura_Companion_FullApp_WithOS_v6_WeeklySnapshotDashboard.zip`
- `Neura_Companion_FullApp_WithOS_v10_3DViewer_VS_CI_Rigs.zip`
- `Neura_Companion_Memory_Visualization_Legacy_Safeguards.zip`
- `Neura_Companion_OS_Rebuilt_WithUpdates_v2.zip`
- `Neura_Companion_Relationship_DeepDive_Addon (1).zip`
- `Neura_Companion_Relationship_UpgradePack.zip`
- `Neura_Companion_Voice_Emotion_Legacy_Patch.zip`
- `Neura_Content_Generation_Core.zip`
- `Neura_Creator_Engine.zip` — duplicate copy: `(1)`
- `Neura_Emotion_Lighting_System.zip`
- `Neura_Encrypted_Memory_Graph.zip`
- `Neura_Ethical_Autonomy_Guardrails.zip`
- `Neura_Final_MegaBuild.zip`
- `Neura_Intent_Engine_Weaving.zip`
- `Neura_Joy_Engine.zip`
- `Neura_LegacyModule_Patch_v2.zip`
- `Neura_LegacyModule_Patch_v4.zip`
- `Neura_Living_System_Patch_Modules1-6.zip`
- `Neura_Living_System_Patch_Modules7-9.zip`
- `Neura_MirrorMood_ThemeDifficulty_Pack (1).zip`
- `Neura_OS_Complete_Merged.zip` — duplicate copy: `(1)`
- `Neura_OS_Core_Skeleton.zip`
- `Neura_OS_Focus_Mode_Pack.zip`
- `Neura_OS_MoodReactive_Shell_Pack.zip`
- `Neura_OS_Patch_FocusAmbientRooms_v8.zip` — duplicate copy: `(1)`
- `Neura_OS_Persona_Tone_Pack.zip` — duplicate copies: `(2)`, `(3)`
- `Neura_OS_RiveRig_King_Done.zip`
- `Neura_OS_Session_Engine_Pack.zip`
- `Neura_OS_Unified_FullBuild.zip`
- `Neura_OS_Upgraded_With_Legacy_v2.zip`
- `Neura_OS_Upgraded_With_Legacy_v3.zip`
- `Neura_OS_Upgraded_With_Legacy_v4.zip`
- `Neura_OS_Upgraded_With_Legacy_v6.zip`
- `Neura_OS_Upgraded_With_Legacy_v8.zip` — duplicate copy: `(1)`
- `Neura_OS_Values_Compass_Pack.zip`
- `Neura_OS_With_NeuraSpaces_v7.zip` — duplicate copy: `(1)`
- `Neura_OsShell_Integration_Pack.zip`
- `Neura_Persona_Integration_Pack.zip`
- `Neura_Persona_Weekly_Dream_Mood_Pack.zip`
- `Neura_Reflection_Meaning_Engine.zip`
- `Neura_RiveResident_VisemeWalk_Patch_v4.zip`
- `Neura_System_Module1-3_PATCH.zip`
- `Neura_Unity_Flutter_Bridge.zip`
- `Neura_Unity_World_Core.zip`
- `Neura_WeeklySnapshot_DreamShow2_Pack.zip`
- `neura_companion_FINISHED_v17_1.zip` — duplicate copy: `(1)`
- `neura_v17_0_min_bundle.zip`

## Recovery decision

**Green:** Current source, dependency definitions, recent functional work, and the removed legacy packs are recoverable from GitHub.  
**Amber:** Drive historical packs and build guides are readable but incomplete, duplicated, and stale; retain them only as reference.  
**Red:** Current binary/installer, Android signing, external monetization deployment, fresh checksums, and end-user data are not proven backed up.

The safest reconstruction is therefore: **pin GitHub head → make a full-history bundle → export pre-cleanup history separately → validate Flutter → restore external configuration → build and test fresh artifacts → generate new checksums → archive source, binaries, environment, and user data independently.**
