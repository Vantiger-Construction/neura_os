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
