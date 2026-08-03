# Neura recovery and deterministic repair

This directory preserves the July 2026 recovery evidence and the measured
Flutter analyzer repair brief used to recover the canonical Neura app.

## Source of truth

- Current app source: repository root on branch `Neura`.
- Expected Flutter package name: `neuro_companion`.
- Historical and nested project copies are evidence only; do not bulk-overlay
  them onto the root project.
- Repair work must be measured after each change, and load-bearing services
  must be repaired in place rather than deleted or quarantined.

Read these before performing recovery work:

1. `Neura_Recovery_Manifest_2026-07-27.md`
2. `NEURA_CLAUDE_CODE_BRIEF.md`

## Preferred Windows command

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\Neura_Update_And_Prepare.ps1 `
  -Root "$PWD"
```

The script validates the root, runs conservative Dart text repair, refreshes
packages, enforces a zero-error analyzer gate, runs tests, and creates a
Windows release build. It does not merge forks or package the final installer.

For analyzer preparation only, run:

```bat
neura_prep.bat
```

Repair output and backups are written under `.neura_repair` and are excluded
from source control.

## Recovered-source packaging

For a recovered package that contains `source\rebuilt_flutter`, or to build the
canonical repository root from an isolated staging copy, use:

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\tools\Build-Neura-GoogleDriveRebuild.ps1 `
  -Yes
```

The builder regenerates only missing platform scaffolds, restores the authored
Flutter files, requires dependency/analyzer/test gates, creates a Windows
release ZIP, and writes SHA-256 checksums. See
`GOOGLE_DRIVE_REBUILD_BUILD.md` for the complete process and limitations.
