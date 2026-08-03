# Google Drive rebuilt-source builder

`tools/Build-Neura-GoogleDriveRebuild.ps1` turns an intact recovered Flutter
source snapshot into a validated portable Windows release ZIP. It is designed
for recovery work and deliberately builds from an isolated copy instead of
changing the source snapshot in place.

## Source-of-truth warning

The current repository root on branch `Neura` remains the authoritative Neura
application. Historical Drive packages and nested project copies are recovery
evidence only. Do not bulk-overlay them onto the root project.

This builder prefers the following recovered-package layout when it exists:

```text
<PackageRoot>/
  source/
    rebuilt_flutter/
      pubspec.yaml
      lib/
        main.dart
  tools/
    Build-Neura-GoogleDriveRebuild.ps1
    BUILD_GOOGLE_DRIVE_REBUILD.cmd
  dist/
```

When `source/rebuilt_flutter` is absent and `PackageRoot` itself contains
`pubspec.yaml` plus `lib/main.dart`, the script can build the canonical
repository root from an isolated staging copy. You can always pin the input
explicitly with `-SourceRoot`.

## Requirements

- Windows PowerShell 5.1 or newer
- Flutter stable
- Visual Studio 2022 with **Desktop development with C++**
- A compatible Windows SDK
- Android SDK, Java, and Flutter Android tooling only when `-BuildAndroid` is
  requested

## Run from the repository or package root

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\tools\Build-Neura-GoogleDriveRebuild.ps1 `
  -Yes
```

Or use the launcher:

```bat
tools\BUILD_GOOGLE_DRIVE_REBUILD.cmd -Yes
```

To select a recovered source explicitly:

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\tools\Build-Neura-GoogleDriveRebuild.ps1 `
  -PackageRoot "D:\NeuraRecovery" `
  -SourceRoot "D:\NeuraRecovery\source\rebuilt_flutter" `
  -FlutterPath "C:\src\flutter\bin\flutter.bat" `
  -Yes
```

To include Android:

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\tools\Build-Neura-GoogleDriveRebuild.ps1 `
  -BuildAndroid `
  -Yes
```

Tests are required by default. Use `-SkipTests` only for diagnostic builds, not
for a release candidate.

## What the script does

1. Resolves and validates the package root and Flutter source.
2. Locates `flutter.bat` from `-FlutterPath`, `PATH`, or common install paths.
3. Copies the source to a timestamped staging directory under:

   ```text
   %LOCALAPPDATA%\NeuraCompanion\Builds\DriveRebuild_<timestamp>
   ```

4. Excludes source-control and generated caches from the staging copy.
5. Preserves authored `lib`, `test`, `assets`, `pubspec.yaml`,
   `pubspec.lock`, analysis configuration, localization configuration, and
   README files.
6. Runs `flutter create` only to generate missing Windows and Android
   platform scaffolds.
7. Restores the authored files immediately after scaffold generation.
8. Runs `flutter pub get`.
9. Requires `flutter analyze --no-fatal-warnings --no-fatal-infos` to exit
   successfully.
10. Runs `flutter test --reporter expanded` unless `-SkipTests` is supplied.
11. Builds a Windows x64 release.
12. Optionally builds an Android release APK.
13. Adds `README_INSTALL.txt` and `BUILD_MANIFEST.json` to the Windows release.
14. Creates portable ZIP/APK outputs and SHA-256 checksum files under `dist`.

## Output

Typical Windows output:

```text
dist/
  NeuraCompanion_GoogleDriveRebuild_Windows_x64_1.1.0.zip
  NeuraCompanion_GoogleDriveRebuild_Windows_x64_1.1.0_SHA256.txt
  DriveRebuild_build_<timestamp>.log
```

Optional Android output:

```text
dist/
  NeuraCompanion_GoogleDriveRebuild_Android_1.1.0.apk
  NeuraCompanion_GoogleDriveRebuild_Android_1.1.0_SHA256.txt
```

## Safety behavior

- The original recovered source is never built or modified in place.
- The script does not merge sibling forks.
- It does not delete or quarantine load-bearing app services.
- It does not add features or change Flutter behavior.
- It stops on dependency, analyzer, test, or compiler failure.
- It preserves the staging folder and log for diagnosis.
- The resulting ZIP is a portable release package, not an installer.

## Important limitation

The repository does not currently contain a verified complete
`source/rebuilt_flutter` Drive snapshot. Adding this builder does not prove that
historical Drive source is complete, nor does it recover local user data,
secrets, signing keys, or deployed external services. Use the canonical root
whenever the recovered snapshot is incomplete.
