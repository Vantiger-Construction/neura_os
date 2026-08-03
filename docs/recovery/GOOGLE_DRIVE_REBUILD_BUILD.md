# Google Drive rebuilt-source builder

`tools/Build-Neura-GoogleDriveRebuild.ps1` turns an intact recovered Flutter
source snapshot into validated Windows release artifacts. It always creates a
portable ZIP and can also create a per-user Windows installer through Inno
Setup. Recovery builds run from an isolated copy instead of modifying the
source snapshot in place.

## Source-of-truth warning

The current repository root on branch `Neura` remains the authoritative Neura
application. Historical Drive packages and nested project copies are recovery
evidence only. Do not bulk-overlay them onto the root project.

The builder prefers this recovered-package layout when it exists:

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
    BUILD_GOOGLE_DRIVE_REBUILD_INSTALLER.cmd
    installer/
      NeuraCompanion.iss
  dist/
```

When `source/rebuilt_flutter` is absent and `PackageRoot` itself contains
`pubspec.yaml` plus `lib/main.dart`, the script builds the canonical repository
root from an isolated staging copy. You can pin the input explicitly with
`-SourceRoot`.

## Requirements

Portable Windows build:

- Windows PowerShell 5.1 or newer
- Flutter stable
- Visual Studio 2022 with **Desktop development with C++**
- A compatible Windows SDK

Optional installer:

- Inno Setup 6, with `ISCC.exe` on `PATH`, in a standard installation folder,
  or supplied through `-InnoSetupPath`

Optional Android build:

- Android SDK
- Java required by the selected Flutter/Gradle toolchain
- Flutter Android tooling configured successfully

## Portable release command

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\tools\Build-Neura-GoogleDriveRebuild.ps1 `
  -Yes
```

Or:

```bat
tools\BUILD_GOOGLE_DRIVE_REBUILD.cmd -Yes
```

## Windows installer command

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\tools\Build-Neura-GoogleDriveRebuild.ps1 `
  -BuildInstaller `
  -Yes
```

Or use the installer launcher:

```bat
tools\BUILD_GOOGLE_DRIVE_REBUILD_INSTALLER.cmd -Yes
```

When Inno Setup is installed somewhere nonstandard:

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\tools\Build-Neura-GoogleDriveRebuild.ps1 `
  -BuildInstaller `
  -InnoSetupPath "D:\Tools\Inno Setup 6\ISCC.exe" `
  -Yes
```

The installer defaults to:

```text
%LOCALAPPDATA%\Programs\Neura Companion
```

The install wizard keeps the location page enabled, so the user can choose a
different destination. Installation uses the current Windows user and does not
require writing to Program Files.

## Select a recovered source explicitly

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\tools\Build-Neura-GoogleDriveRebuild.ps1 `
  -PackageRoot "D:\NeuraRecovery" `
  -SourceRoot "D:\NeuraRecovery\source\rebuilt_flutter" `
  -FlutterPath "C:\src\flutter\bin\flutter.bat" `
  -BuildInstaller `
  -Yes
```

## Include Android

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\tools\Build-Neura-GoogleDriveRebuild.ps1 `
  -BuildAndroid `
  -BuildInstaller `
  -Yes
```

Tests are required by default. Use `-SkipTests` only for diagnostic builds,
not for a release candidate.

## Version controls

Defaults:

```text
BuildName   = 1.1.0
BuildNumber = 2
```

Override them together for a release:

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\tools\Build-Neura-GoogleDriveRebuild.ps1 `
  -BuildName "1.2.0" `
  -BuildNumber 3 `
  -BuildInstaller `
  -Yes
```

`BuildName` is used in Flutter build metadata and output names. `BuildNumber`
must be at least 1.

## What the script does

1. Resolves and validates the package root and Flutter source.
2. Locates `flutter.bat` from `-FlutterPath`, `PATH`, or common install paths.
3. Locates `ISCC.exe` only when `-BuildInstaller` is requested.
4. Copies the source to a timestamped staging directory under:

   ```text
   %LOCALAPPDATA%\NeuraCompanion\Builds\DriveRebuild_<timestamp>
   ```

5. Excludes source-control and generated caches from the staging copy.
6. Preserves authored `lib`, `test`, `assets`, Windows and Android platform
   customizations, `pubspec.yaml`, `pubspec.lock`, analysis configuration,
   localization configuration, and README files.
7. Runs `flutter create` only to add required platform scaffolding.
8. Restores authored source and overlays authored platform customizations.
9. Runs `flutter pub get`.
10. Requires `flutter analyze --no-fatal-warnings --no-fatal-infos` to exit
    successfully.
11. Runs `flutter test --reporter expanded` unless `-SkipTests` is supplied.
12. Builds a Windows x64 release.
13. Optionally builds an Android release APK.
14. Adds `README_INSTALL.txt`, `BUILD_MANIFEST.json`, and
    `TOOLCHAIN_MANIFEST.txt` to the Windows release.
15. Creates portable ZIP/APK outputs and SHA-256 checksum files under `dist`.
16. When requested, compiles `tools/installer/NeuraCompanion.iss` against the
    verified Windows Release directory and hashes the resulting setup EXE.

## Output

Typical portable Windows output:

```text
dist/
  NeuraCompanion_GoogleDriveRebuild_Windows_x64_1.1.0.zip
  NeuraCompanion_GoogleDriveRebuild_Windows_x64_1.1.0_SHA256.txt
  DriveRebuild_build_<timestamp>.log
```

Optional installer output:

```text
dist/
  NeuraCompanion_Setup_1.1.0.exe
  NeuraCompanion_Setup_1.1.0_SHA256.txt
```

Optional Android output:

```text
dist/
  NeuraCompanion_GoogleDriveRebuild_Android_1.1.0.apk
  NeuraCompanion_GoogleDriveRebuild_Android_1.1.0_SHA256.txt
```

The Windows ZIP and installer contain the complete Flutter Release directory,
including the executable, DLLs, plugins, `data` folder, install README, build
manifest, and toolchain manifest.

## Installer behavior

The checked-in Inno Setup source provides:

- Stable Neura Companion application identity for upgrades
- User-selectable install directory
- Per-user installation by default
- Start menu shortcut
- Optional desktop shortcut
- Launch-after-install option
- Recursive inclusion of the verified Flutter Release directory
- Uninstall support

The setup EXE is **unsigned by default**. Before public distribution, sign the
installer with an appropriate Windows code-signing certificate and verify the
signature on a clean machine. Do not treat compilation alone as code-signing
or SmartScreen reputation.

## Safety behavior

- The original recovered source is never built or modified in place.
- The script does not merge sibling forks.
- It does not delete or quarantine load-bearing app services.
- It does not add features or change Flutter behavior.
- It stops on dependency, analyzer, test, compiler, packaging, or requested
  installer failure.
- It preserves the staging folder and log for diagnosis.
- The portable ZIP remains available even when installer compilation is not
  requested.
- Generated installer environment variables are restored after compilation.

## Release validation still required

A successful script exit proves the automated build gates completed on that
machine. Before calling the artifact production-ready, also verify:

1. The ZIP extracts and launches on a clean Windows profile.
2. The installer installs, launches, upgrades, repairs, and uninstalls.
3. App data retention behavior matches the product policy.
4. The app starts with the network blocked.
5. Microphone denial, TTS/STT, avatar windows, journal persistence, premium
   screen, and close/relaunch paths work.
6. Every distributed artifact matches its recorded SHA-256.
7. The setup EXE is signed when intended for public distribution.

## Important limitation

The repository does not currently contain a verified complete
`source/rebuilt_flutter` Drive snapshot. Adding this builder does not prove that
historical Drive source is complete, nor does it recover local user data,
secrets, Android signing keys, Windows signing certificates, or deployed
external services. Use the canonical root whenever the recovered snapshot is
incomplete.
