# Neura pipeline integration

The package is stored in `tools/neura_dart_repair` and can also be installed as a per-user Windows utility.

At the beginning of another Neura build batch file, after the project root is determined, add:

```bat
call "%NEURA_ROOT%\tools\neura_dart_repair\pipeline\PREBUILD_NEURA_REPAIR.cmd" "%NEURA_ROOT%"
if errorlevel 1 exit /b %errorlevel%
```

This creates a fail-fast gate:

1. Locate and validate the Flutter root (`pubspec.yaml` plus `lib`).
2. Normalize smart quotes and invisible Unicode corruption.
3. Run the Dart/Flutter analyzer from the project root.
4. Apply only analyzer-targeted, conservative delimiter repairs.
5. Re-run analysis and roll back a repair pass if the error count increases.
6. Stop the build if analyzer errors remain.

For a complete Flutter build:

```bat
tools\neura_dart_repair\pipeline\BUILD_NEURA_FLUTTER_FULL.cmd D:\Vantiger1\neura_os
```

For the repository's stricter clean/analyze/test/Windows-release sequence, use the root-level `Neura_Update_And_Prepare.ps1` instead.
