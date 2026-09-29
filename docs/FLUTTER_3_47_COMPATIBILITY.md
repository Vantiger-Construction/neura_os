# Flutter 3.47 compatibility gate

This change set upgrades Neura OS's pinned validation toolchain to Flutter
3.47.5 and deliberately keeps the migration separate from feature work. It is
a compatibility gate, not a release approval.

## Pinned Android toolchain

- Flutter 3.47.5 (stable)
- Dart 3.13.4 from the pinned Flutter SDK. Dependency resolution records a
  Dart 3.12 floor, while the package language-version floor remains at Dart
  3.0 to keep a repository-wide formatter migration out of this gate.
- Android Gradle Plugin 9.1.0
- Gradle 9.3.1
- Java 17
- Android compile SDK 36 (through `flutter.compileSdkVersion`)
- Android NDK 28.2.13676358 (through `flutter.ndkVersion`)
- AGP built-in Kotlin enabled with `android.builtInKotlin=true`

The app no longer applies the legacy Kotlin Android Gradle plugin. Kotlin JVM
targeting moves to the typed `kotlin.compilerOptions` DSL required by the
Flutter 3.47 app template.

## Merge gates

The draft must remain unmerged until all of the following are demonstrated on
the retained Windows/Android runner:

1. `flutter pub get` succeeds from the committed lockfile without an
   unreviewed dependency upgrade, and leaves `pubspec.lock` unchanged.
2. `flutter analyze --fatal-infos` and the full Flutter test suite pass.
3. The Windows release build starts in normal mode and Safe Mode; text entry,
   IME composition, accessibility focus, local speech capture, and microphone
   denial are exercised.
4. The Android debug APK builds, installs, launches, survives background and
   foreground transitions, and preserves encrypted local state across restart.
5. Every Android plugin is audited for AGP 9 built-in Kotlin compatibility.
   Any plugin still applying `org.jetbrains.kotlin.android` blocks the merge.
6. Release artifact hashes and package-layout checks remain unchanged.

## Resolved Android plugin audit (2026-09-27)

Scope: the exact `pubspec.lock` at requested head
`b43ed36b5ec90c4afe60d508ee972450aeb904c8`. Dependency inputs and the
lockfile were unchanged at live PR head
`e1cfd8b83ecbef232896646d1332c97edc2c62e1` when this audit was
performed.

The audit read each selected package's published archive and inspected its
Flutter plugin declaration, Android manifest, and Android Gradle scripts. A
package which applies `kotlin-android` or
`org.jetbrains.kotlin.android` is a hard blocker under the gate above. A
package with no such application is only a **static pass**: it still requires
the retained Android APK/device gate. The upstream AGP baseline records what
the package itself tests; it is not evidence that Neura's AGP 9.1.0 build has
passed.

This criterion follows Flutter's [official built-in Kotlin migration
guide](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers),
including its Flutter 3.47 requirement for `android.builtInKotlin=true`, and
Android's [AGP 9 built-in Kotlin
guidance](https://developer.android.com/build/migrate-to-built-in-kotlin),
which treats the external Kotlin Android plugin as incompatible with the new
DSL.

The self-hosted failure observed for this PR occurs in the non-system-volume
storage gate before checkout. It is infrastructure evidence only. It does not
exercise the lockfile, Gradle, AGP, Kotlin, compilation, installation, launch,
or device behavior and is excluded from every compatibility conclusion below.

| Resolved Android implementation | Selected route | Published Android evidence | AGP 9 / built-in Kotlin status | Risk and smallest correction |
| --- | --- | --- | --- | --- |
| [`app_links` 7.2.1](https://pub.dev/packages/app_links/versions/7.2.1) | direct | Java; namespace present; upstream AGP 9.2.1 | Static pass: no external Kotlin plugin | Low static risk; no dependency change. APK/device gate remains. |
| [`audioplayers_android` 5.3.0](https://pub.dev/packages/audioplayers_android/versions/5.3.0) | `audioplayers` 6.8.1 | Kotlin; namespace present; upstream AGP 7.3.1 | Static pass: no external Kotlin plugin | Medium until AGP 9 build because the upstream baseline is old; no demonstrated dependency correction. |
| [`connectivity_plus` 6.1.5](https://pub.dev/packages/connectivity_plus/versions/6.1.5) | direct | Java; namespace present; upstream AGP 8.3.1 | Static pass: no external Kotlin plugin | Low static risk; no dependency change. |
| [`file_picker` 10.3.10](https://pub.dev/packages/file_picker/versions/10.3.10) | direct | Kotlin; namespace present; upstream AGP 8.5.1; applies `org.jetbrains.kotlin.android` | **Blocked** | `file_picker` 11.0.0 is the independent migration floor, but the full correction set's `share_plus` floor conflicts through `win32`; the joint floor is 12.0.0 and requires FilePicker API review. |
| [`flutter_local_notifications` 22.3.1](https://pub.dev/packages/flutter_local_notifications/versions/22.3.1) | direct | Java; namespace present; upstream AGP 8.11.1 | Static pass: no external Kotlin plugin | Low static risk; no dependency change. |
| [`flutter_plugin_android_lifecycle` 2.0.35](https://pub.dev/packages/flutter_plugin_android_lifecycle/versions/2.0.35) | transitive Flutter plugin | Java; namespace present; upstream AGP 8.13.1 | Static pass: no external Kotlin plugin | Low static risk; no dependency change. |
| [`flutter_secure_storage` 9.2.4](https://pub.dev/packages/flutter_secure_storage/versions/9.2.4) | direct | Java; conditional namespace present; upstream AGP 8.5.1 | Static pass: no external Kotlin plugin | Keep pinned. A later `share_plus` correction creates a separate `win32` solver conflict; do not broaden this security-sensitive migration inside the compatibility gate. |
| [`flutter_tts` 4.2.5](https://pub.dev/packages/flutter_tts/versions/4.2.5) | direct | Kotlin; namespace present; upstream AGP 8.13.0; applies `kotlin-android` | **Blocked** | No published compatible release exists. Upstream PR [#658](https://github.com/dlutton/flutter_tts/pull/658) removes the plugin but is unmerged; wait for a reviewed release or separately review/vendor only that patch. |
| [`home_widget` 0.7.0+1](https://pub.dev/packages/home_widget/versions/0.7.0%2B1) | direct | Kotlin; namespace present; upstream AGP 8.1.2; applies `kotlin-android` | **Blocked** | 0.9.2+1 is the first release whose Android script conditionally avoids the legacy Kotlin plugin under AGP 9. Review intervening breaking changes and run widget/device gates. |
| [`image_picker_android` 0.8.13+23](https://pub.dev/packages/image_picker_android/versions/0.8.13%2B23) | `image_picker` 1.2.3 | Kotlin; namespace present; upstream AGP 8.13.1 | Static pass: no external Kotlin plugin | Low static risk; no dependency change. |
| [`in_app_purchase_android` 0.5.3](https://pub.dev/packages/in_app_purchase_android/versions/0.5.3) | `in_app_purchase` 3.3.0 | Kotlin; namespace present; upstream AGP 8.13.1 | Static pass: no external Kotlin plugin | Low static risk; no dependency change. |
| [`jni` 1.0.3](https://pub.dev/packages/jni/versions/1.0.3) | `path_provider_android` 2.3.1 | Java Android plugin; namespace present; no standalone AGP pin | Static pass: no external Kotlin plugin | Low static risk; no dependency change. |
| [`jni_flutter` 1.0.3](https://pub.dev/packages/jni_flutter/versions/1.0.3) | `path_provider_android` 2.3.1 | Java Android plugin; namespace present; no standalone AGP pin | Static pass: no external Kotlin plugin | Low static risk; no dependency change. |
| [`local_auth_android` 1.0.56](https://pub.dev/packages/local_auth_android/versions/1.0.56) | `local_auth` 2.3.0 | Java; namespace present; upstream AGP 8.12.1 | Static pass: no external Kotlin plugin | Low static risk; retain authentication/device gates. |
| [`path_provider_android` 2.3.1](https://pub.dev/packages/path_provider_android/versions/2.3.1) | `path_provider` 2.1.6 | Dart-only Android implementation; no Android Gradle module | Static pass: Kotlin/AGP script check not applicable | Low static risk; no dependency change. |
| [`permission_handler_android` 12.1.0](https://pub.dev/packages/permission_handler_android/versions/12.1.0) | `permission_handler` 11.4.0 | Java; namespace present; upstream AGP 8.0.0 | Static pass: no external Kotlin plugin | Medium until AGP 9 build; retain denial and Safe Mode device tests. |
| [`printing` 5.15.0](https://pub.dev/packages/printing/versions/5.15.0) | direct | Java; namespace present; upstream AGP 7.3.0 | Static pass: no external Kotlin plugin | Medium until AGP 9 build because the upstream baseline is old; no demonstrated dependency correction. |
| [`record_android` 1.5.2](https://pub.dev/packages/record_android/versions/1.5.2) | `record` 6.2.1 | Kotlin; namespace present; upstream AGP 8.12.3; applies `kotlin-android` | **Blocked**; confirmed by upstream issue [#614](https://github.com/llfbandit/record/issues/614) | Upgrade `record` to 7.0.0 or later and require resolved `record_android` 2.1.2 or later. Review removal of the Android background recording service; retain local-only microphone and Safe Mode gates. |
| [`share_plus` 7.2.2](https://pub.dev/packages/share_plus/versions/7.2.2) | direct | Kotlin; namespace present; upstream AGP 8.2.0; applies `kotlin-android` | **Blocked** | 13.2.0 is the first published built-in-Kotlin release, but its `win32` requirement conflicts with the current secure-storage chain and would force a security-sensitive major migration. Isolate that review. |
| [`shared_preferences_android` 2.4.28](https://pub.dev/packages/shared_preferences_android/versions/2.4.28) | `shared_preferences` 2.5.5 | Kotlin; namespace present; upstream AGP 8.13.1 | Static pass: no external Kotlin plugin | Low static risk; no dependency change. |
| [`speech_to_text` 7.4.0](https://pub.dev/packages/speech_to_text/versions/7.4.0) | direct | Kotlin; namespace present; upstream AGP 8.9.1; applies `kotlin-android` | **Blocked** | 7.5.0 is the focused built-in-Kotlin migration. Retain local speech, denial, and Safe Mode device tests. |
| [`url_launcher_android` 6.3.33](https://pub.dev/packages/url_launcher_android/versions/6.3.33) | `url_launcher` 6.3.2 | Kotlin/Java; namespace present; upstream AGP 8.13.1 | Static pass: no external Kotlin plugin | Low static risk; no dependency change. |

### Dependency correction decision

There is no narrow, published dependency-only change set that clears all six
blockers:

- `record` 7.0.0+, `record_android` 2.1.2+, `home_widget` 0.9.2+1, and
  `speech_to_text` 7.5.0 have published built-in-Kotlin paths.
- `file_picker` 11.0.0 is its independent migration floor, but the combined
  graph with `share_plus` 13.2.0 requires `file_picker` 12.0.0 because the two
  floors require incompatible `win32` major versions.
- `share_plus` 13.2.0 also conflicts with the current
  `flutter_secure_storage` 9.x Windows chain, forcing a broad and
  security-sensitive secure-storage major upgrade.
- `flutter_tts` has no published built-in-Kotlin release. Pinning an unmerged
  contributor branch would replace one demonstrated blocker with an
  unreviewed supply-chain and maintenance risk.

For that reason this audit intentionally makes **no partial dependency or
lockfile change**. Partial upgrades cannot open the merge gate and would add
behavioral/API risk to Neura's recording, speech, widget, sharing, file, and
encrypted-storage boundaries. Keep this PR draft and blocked. Resolve the six
packages in a separately reviewable dependency remediation change, preserving
Flutter 3.47.5, AGP 9.1.0, Gradle 9.3.1, Java 17,
`android.builtInKotlin=true`, the existing release/device gates, local-only
capture, microphone denial/Safe Mode behavior, and encrypted-state checks.

## UI package decision

Flutter 3.47 offers standalone Material and Cupertino packages, but this gate
does not migrate imports. The framework libraries remain supported in this
release, while mixing framework and standalone widget types can create
dependency-boundary incompatibilities. A package migration therefore needs a
separate dependency inventory, golden-test baseline, and rollback plan.

## Windows renderer decision

No renderer flag is changed here. Validate the Flutter 3.47 default renderer
on representative integrated and discrete GPUs before changing production
defaults. Capture startup failures, device-loss recovery, suspend/resume,
multi-window behavior, and idle memory. A renderer experiment must retain a
documented runtime rollback path.

## Dart language-version decision

This gate runs the app on Flutter 3.47.5's bundled Dart 3.13.4 toolchain
without raising the package's minimum Dart language version. Raising that
floor changes the canonical formatter for existing sources and would mix a
broad mechanical rewrite into the runtime migration. Make that repository-wide
formatter change in a separate PR with an independently reviewable diff.

## Rollback

Revert this single compatibility commit to restore Flutter 3.44.7, AGP 8.11.1,
Gradle 8.14, and the legacy Kotlin Gradle plugin. Do not partially roll back the
Gradle wrapper, AGP, or built-in Kotlin setting; those versions form one tested
unit.
