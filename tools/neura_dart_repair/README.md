# Neura Dart Repair 1.0

Repository location: `tools/neura_dart_repair`. The root-level `fix_smart_quotes.ps1` remains a backward-compatible launcher.

A hardened replacement for the original broad `fix_smart_quotes.ps1` implementation.

## Install on Windows

Double-click:

```text
INSTALL_NEURA_DART_REPAIR.cmd
```

The script installs per-user under `%LOCALAPPDATA%\Programs\Neura Dart Repair` and creates Start Menu and Desktop shortcuts. No administrator rights are required.

## Run from the repository

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\neura_dart_repair\tools\Neura-DartRepair.ps1 -Root D:\Vantiger1\neura_os -RunAnalyzer -AutoFixStringLiterals
```

Preview without modifying files:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\neura_dart_repair\tools\Neura-DartRepair.ps1 -Root D:\Vantiger1\neura_os -WhatIf
```

Restore the newest repair backup:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\neura_dart_repair\tools\Neura-DartRepair.ps1 -Root D:\Vantiger1\neura_os -RestoreLatestBackup
```

## Repairs performed

- Curly single and double quotes, low quotes, and prime characters.
- Non-breaking spaces, zero-width spaces, word joiners, and embedded BOM characters.
- Analyzer-confirmed simple apostrophe corruption such as a single-quoted `don't` string.
- UTF-8 preservation, including the existing BOM choice.

The tool does not broadly rewrite every line containing several quotes. It only attempts string delimiter changes on analyzer-targeted lines and rolls back a pass when the analyzer error count gets worse.

## Compiled EXE installer

`installer\NeuraDartRepair.iss` is ready for Inno Setup 6. Open it in Inno Setup and click **Compile**. The generated installer will be under `installer\output` and is ignored by Git.

The `.iss` project packages the repair utility, not the Neura application itself.
