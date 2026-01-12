# Neura Companion — Final Merge Report

Generated: 2026-01-08T21:42:06.545329Z

## Base
- Started from: Neura_Companion_OS_ALL_IN_ONE_FINAL.zip

## Applied Inputs
- Neura_Companion_FINAL_CLOSED_BETA.zip (included as reference; no Flutter root detected)
- Neura_Companion_FULL_APP_DELIVERY (1).zip (nested patch zips applied)
- Neura_OS_Unified_FullBuild_AdaptiveDecorModulation.zip
- Neura_Decorator_Brain_Patch.zip
- Neura_OS_Unified_FullBuild_MemoryConditionedSpaces.zip
- Neura_OneClick_Installer_Kit.zip -> copied into `tools/oneclick_installer_kit/`
- Neura_Distribution_Packaging_Kit.zip -> copied into `tools/distribution_packaging_kit/`

## Files Added
- Added 53 Dart files under `lib/` (core/behavior/memory/brain/decor_modulation)
- Added placeholder UI audio WAVs under `assets/audio/ui/`
- Updated `pubspec.yaml` assets to include `assets/audio/`
- Added packaging tools under `tools/`

## Conflicts
- Dart conflicts: 0
- Non-dart conflicts: 0

## How to Verify Locally (must be run on your machine with Flutter)
```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run
```

### Build targets
- Android (AAB): `flutter build appbundle --release`
- Windows (MSIX): see `tools/distribution_packaging_kit/windows/MSIX/README_MSIX.md`
- macOS notarization: see `tools/distribution_packaging_kit/mac/NOTARIZATION/README_NOTARIZATION.md`

## Merge Log (high level)
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/core/legacy/legacy_suggester.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/core/legacy/legacy_prompt.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/core/legacy/legacy_bridge.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/core/speech/voice_style.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/core/emotion/emotion_smoothing.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/core/memory/long_term_memory.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/core/legacy/legacy_entry.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/core/legacy/legacy_engine.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/core/memory/visual/memory_timeline_node.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/core/memory/visual/memory_constellation_engine.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/core/legacy/legacy_policy.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/core/legacy/legacy_rule.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/core/legacy/legacy_guardian.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/ui/memory/memory_constellation_view.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/speech/neura_speech_state.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/speech/neura_speech_controller.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/speech/speech_item.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/speech/speech_queue.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/speech/neura_speech_engine.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/world/neura_object.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/world/apartment_objects.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/world/object_interaction_engine.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/world/world_memory.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/neura_system.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/memory/memory_core.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/memory/memory_models.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/memory/memory_store.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/memory/memory_encryptor.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/memory/memory_summarizer.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/memory/memory.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/emotion/emotion_core.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/emotion/emotion_state.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/emotion/emotion_trends.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/emotion/emotion_analyzer.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/emotion/emotion_store.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/patch_incoming/emotion/emotion.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/behavior/behavior_engine.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/behavior/behavior_decision.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/behavior/behavior_action.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/behavior/context_snapshot.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/behavior/neura_room.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/behavior/suppression_rules.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/behavior/action_registry.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/behavior/behavior.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/decor_modulation/adaptive_decor_modulation_service.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/decor_modulation/adaptive_decor_signal_pump.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/brain/decorator_brain.dart
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/lib/memory/space_memory_engine.dart
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/distribution_packaging_kit/./ROADMAP_V1_2_QUIET_GROWTH.md
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/distribution_packaging_kit/windows/MSIX/README_MSIX.md
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/distribution_packaging_kit/windows/MSIX/msix_config_example.yaml
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/distribution_packaging_kit/windows/MSIX/Build-MSIX.ps1
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/distribution_packaging_kit/windows/MSIX/Build-MSIX.bat
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/distribution_packaging_kit/android/PLAY/README_PLAY_AAB.md
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/distribution_packaging_kit/android/PLAY/github_actions_android_aab.yml
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/distribution_packaging_kit/android/PLAY/PLAY_CONSOLE_TRACK_NOTES.md
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/distribution_packaging_kit/mac/NOTARIZATION/README_NOTARIZATION.md
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/distribution_packaging_kit/mac/NOTARIZATION/sign_and_notarize.sh
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/oneclick_installer_kit/./README.md
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/oneclick_installer_kit/./STORE_SUBMISSION_BUILD_CHECKLIST.md
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/oneclick_installer_kit/./MANIFEST.json
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/oneclick_installer_kit/./CHECKSUMS_SHA256.txt
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/oneclick_installer_kit/windows/Install-Neura-Windows.ps1
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/oneclick_installer_kit/windows/Install-Neura-Windows.bat
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/oneclick_installer_kit/android/Build-Neura-Android.sh
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/oneclick_installer_kit/android/Build-Neura-Android.bat
- ADD(non-dart): /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/tools/oneclick_installer_kit/mac/Build-Neura-macOS.sh
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/assets/audio/ui/hover_star.wav
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/assets/audio/ui/select_star.wav
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/assets/audio/ui/chapter_form.wav
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/assets/audio/ui/chapter_prompt.wav
- ADD: /mnt/data/neura_final_merge_work/Neura_Companion_OS_ALL_IN_ONE_FINAL/assets/audio/ui/chapter_confirm.wav
