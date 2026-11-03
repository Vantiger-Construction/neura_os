# Neura OS (Merged Build)

This is the **merged** Neura OS Flutter project with the upgrades/patches you uploaded applied into one codebase.

## GitHub coding agents

Six [Neura specialist agents](docs/GITHUB_AGENTS.md) cover CI repair, privacy and
memory, voice and avatar, offline intelligence, dependencies, and release
readiness. Select one in GitHub's agent picker for a focused task. Shared project
boundaries and validation commands are in [AGENTS.md](AGENTS.md).

## Included modules
- Legacy Vault
- Neura Spaces (rooms + map)
- Focus Office + Ambient FX
- Mood Check-In + Mood History
- Journal Prompt + Voice Journal
- Dream Visualizer + Dream Calendar + Monthly Dream Show
- Settings + Diagnostics
- **Voice Lab** (offline voice clips + live microphone visemes)

## Neura Engine direction

The [Neura Engine vision and implementation milestones](docs/NEURA_ENGINE_VISION.md)
describe a dedicated engine for ongoing reflection and learning from approved
information, with user control over memory and actions. The
[milestone 1 synthetic IPC slice](docs/NEURA_ENGINE_IPC_M1.md) now includes an
authenticated Rust sidecar and a Windows Console session with explicit
start, pause, resume, and stop controls. It remains a synthetic-only check that
uses the echo adapter by default; an explicit `ollama-local` opt-in can run the
same fixed fixtures on a pinned local model
([milestone 2 slice](docs/NEURA_ENGINE_MODEL_ADAPTER_M2.md)). Milestones 1 and 2
are incomplete, and reflection and personal sources are not enabled.

## Quick start (Windows)

1. Follow the [developer guide](docs/DeveloperGuide.md) to install the SDKs and
   Windows native build prerequisites for this branch.
2. Run `Neura.bat` from the repository root. It repairs shortcuts, verifies or
   builds the payload, and starts Neura through `tools/Start-Neura.ps1`.

For configured packages, see [build configuration](docs/CONFIGURED_BUILDS.md).
An Actions artifact is a development candidate until its identity and relevant
platform/device checks have been verified.

## Manual commands
```bash
flutter pub get --enforce-lockfile
flutter run
# Release build:
flutter build apk --release
```

## Voice assets
Voice samples are bundled at:
- `assets/audio/neura/*.wav`

The Voice Lab screen lets you:
- Play a voice clip
- Toggle live microphone mouth/viseme driver (offline)

## Contributing and support

Use [CONTRIBUTING.md](CONTRIBUTING.md) for the PR workflow and
[SUPPORT.md](SUPPORT.md) for bug reports and questions. Report vulnerabilities
privately using [SECURITY.md](SECURITY.md). The
[repository setup guide](docs/GITHUB_REPOSITORY_SETUP.md) records merge checks
and remaining account prerequisites.
