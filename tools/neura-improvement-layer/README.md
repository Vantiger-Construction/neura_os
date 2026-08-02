# Neura Improvement Layer v1

This package improves an existing Neura checkout without replacing its source code.
It adds deterministic root discovery, preflight diagnostics, safer build orchestration,
API health checks, structured logs, and recovery guidance.

## Use

1. Extract this folder beside or inside your recovered Neura project.
2. Run `NEURA_IMPROVE_AND_BUILD.bat`.
3. Review the generated report under `logs`.

The scripts search common Neura locations and validate the selected root before running anything.
They do not delete source files and do not install dependencies without showing what is missing.

## What it detects

- Unity projects (`Assets`, `ProjectSettings`)
- Flutter projects (`pubspec.yaml`)
- Rust workspaces (`Cargo.toml`)
- Node services (`package.json`)
- Python services (`requirements.txt` or `pyproject.toml`)
- Existing Neura full-build scripts
- Local API health on configurable endpoints

## Important

The two uploaded records reference earlier ZIP packages, but those ZIP files were not available
in the current workspace. This layer is therefore additive and recovery-safe; it does not claim
to contain the missing application source.
