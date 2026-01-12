# Windows MSIX Packaging (Flutter)

This kit packages your Flutter Windows build into an MSIX installer (real installer UX).

## Prereqs
- Windows 10/11
- Flutter SDK on PATH
- Visual Studio Build Tools
- PowerShell 5+
- A code signing cert (recommended). For internal testing you can skip signing.

## Approach
We use the Flutter `msix` package (community standard) which generates an MSIX from your Windows build output.

## One-time setup (inside your Flutter project)
1) Add dependency:
   flutter pub add msix

2) Create or update `msix_config:` in `pubspec.yaml` (see `msix_config_example.yaml` in this folder).

3) Ensure your Windows app identity is correct:
   - `publisher` must match your certificate subject (when signing)
   - `identity_name` should be stable (do not change between updates)

## Build MSIX (one click)
Run:
- `Build-MSIX.ps1` (preferred)
or
- `Build-MSIX.bat`

Outputs:
- `.\build\windows\x64\runner\Release\`
- `./build/msix/*.msix` (exact path printed by script)
